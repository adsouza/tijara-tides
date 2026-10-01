defmodule TijaraTides.Domain.Services.WeatherDelays do
  @moduledoc "Coordinate regional warnings and ship-owned revised voyage timelines."
  alias TijaraTides.Domain.{WeatherWorld, ShipWorld, State, VoyageNavigation, Notices}

  def advance(state, elapsed, catalogue, speedup) do
    state = WeatherWorld.refresh(state, catalogue)

    State.entities(state, "ships")
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce(state, fn {id, ship}, s ->
      if ship["status"] == "sailing" and is_list(VoyageNavigation.path(ship, catalogue)) do
        changed = ShipWorld.apply_weather(s, id, catalogue, elapsed, speedup)
        next = State.get(changed, "ships", id)

        if next["arrive_ms"] != ship["arrive_ms"] do
          company = State.get(changed, "companies", ship["company_id"])

          Notices.notice(
            changed,
            company["account_id"],
            "weather:" <> id,
            {"ship.weather",
             %{
               "ship" => ship["name"],
               "destination" => ship["destination"],
               "minutes" => next["weather"]["delay_ms"] / 60_000
             }}
          )
        else
          changed
        end
      else
        s
      end
    end)
  end
end
