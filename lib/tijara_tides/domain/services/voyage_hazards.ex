defmodule TijaraTides.Domain.Services.VoyageHazards do
  @moduledoc "Resolve attacks and storms in one voyage timeline before fleet cost settlement."
  alias TijaraTides.Domain.{
    WeatherWorld,
    PiracyWorld,
    Piracy,
    Weather,
    ShipWorld,
    ShipClass,
    State,
    VoyageNavigation,
    Notices,
    CompanyFinanceWorld
  }

  def advance(state, elapsed, catalogue, speedup) do
    state = state |> WeatherWorld.refresh(catalogue) |> PiracyWorld.refresh(catalogue)

    State.entities(state, "ships")
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce(state, fn {id, ship}, state ->
      if ship["status"] == "sailing" and is_list(VoyageNavigation.path(ship, catalogue)) do
        state = campaign_notices(state, ship)
        state = ShipWorld.apply_weather(state, id, catalogue, elapsed, speedup)
        {state, hit?} = resolve(state, id, catalogue, elapsed, speedup, false)
        next = State.get(state, "ships", id)

        if not hit? and next["arrive_ms"] != ship["arrive_ms"] do
          company = State.get(state, "companies", ship["company_id"])

          Notices.notice(
            state,
            company["account_id"],
            "weather:" <> id,
            {"ship.weather",
             %{
               "ship" => ship["name"],
               "destination" => ship["destination"],
               "minutes" => storm_delay(next["weather"]) / 60_000
             }}
          )
        else
          state
        end
      else
        state
      end
    end)
  end

  defp storm_delay(weather),
    do:
      Enum.sum(
        for h <- weather["holds"], h["source"] != "piracy", do: h["until_ms"] - h["starts_ms"]
      )

  defp campaign_notices(state, ship) do
    pending = (ship["piracy"] && ship["piracy"]["pending"]) || []
    company = State.get(state, "companies", ship["company_id"])

    Enum.reduce(State.entities(state, "piracy_campaigns"), state, fn {zone, campaign}, state ->
      key = "campaign:" <> campaign["window_id"] <> ":" <> ship["id"]

      if is_nil(company["bankruptcy_ms"]) and Enum.any?(pending, &(&1["zone"] == zone)) and
           is_nil(State.get(state, "notices", key)) do
        model = ship["piracy"]["model"]

        Notices.notice(
          state,
          company["account_id"],
          key,
          {"ship.piracy_campaign",
           %{
             "ship" => ship["name"],
             "zone" => model["zones"][zone]["name"],
             "campaign" => campaign["name"]
           }}
        )
      else
        state
      end
    end)
  end

  defp resolve(state, id, catalogue, elapsed, speedup, hit?) do
    ship = State.get(state, "ships", id)
    crossing = ship["piracy"] && List.first(ship["piracy"]["pending"])

    at =
      crossing && Weather.time_at(ship["weather"], ship["depart_ms"], crossing["attack_fraction"])

    if crossing && at <= state.clock_ms do
      model = ship["piracy"]["model"]
      zone = model["zones"][crossing["zone"]]
      kind = model["kinds"][zone["kind"]]
      class = ShipClass.all()[ship["class"]]
      company = State.get(state, "companies", ship["company_id"])
      guards = ship["piracy"]["protection"] in ["guards", "both"]

      outcome =
        cond do
          company["bankruptcy_ms"] != nil ->
            "exempt"

          Piracy.suppressed?(crossing, ship["depart_ms"], ship["weather"], model) ->
            "suppressed"

          crossing["roll"] <
              Piracy.attack_bps(crossing["zone"], at, model, class["speed"], guards) ->
            "hit"

          true ->
            "missed"
        end

      charge = if outcome == "hit", do: div(class["price"] * kind["charge_bps"], 10_000), else: 0
      insured = ship["piracy"]["protection"] in ["insurance", "both"]
      recovery = if insured, do: div(charge * 80, 100), else: 0
      starts = max(at, ship["last_cost_ms"])
      key = "piracy:" <> id <> ":" <> to_string(crossing["index"])

      incident =
        if outcome == "hit",
          do: %{
            "id" => key,
            "index" => crossing["index"],
            "source" => "piracy",
            "fraction" => crossing["attack_fraction"],
            "zone" => crossing["zone"],
            "zone_name" => zone["name"],
            "kind" => zone["kind"],
            "mark" => kind["mark"],
            "label" => Piracy.kind_label(zone["kind"]),
            "starts_ms" => starts,
            "until_ms" => starts + kind["hold_ms"],
            "charge" => charge,
            "recovery" => recovery
          }

      state =
        ShipWorld.record_crossing(
          state,
          id,
          crossing["index"],
          outcome,
          incident,
          charge,
          recovery
        )

      state =
        if incident do
          state
          |> CompanyFinanceWorld.piracy_charge(company["id"], id, charge, recovery)
          |> Notices.notice(
            company["account_id"],
            key,
            {"ship.piracy",
             %{
               "ship" => ship["name"],
               "zone" => zone["name"],
               "kind" => Piracy.kind_label(zone["kind"]),
               "mark" => kind["mark"],
               "minutes" => kind["hold_ms"] / 60_000,
               "charge" => charge,
               "recovery" => recovery
             }}
          )
        else
          state
        end

      state = ShipWorld.apply_weather(state, id, catalogue, elapsed, speedup)
      resolve(state, id, catalogue, elapsed, speedup, hit? or incident != nil)
    else
      {state, hit?}
    end
  end
end
