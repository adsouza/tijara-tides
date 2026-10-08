defmodule TijaraTides.Domain.Piracy do
  @moduledoc "Pirate zones and deterministic announced campaigns in active-world time."

  @kinds ~w(boarding fleet_piracy militia piracy)

  def model(catalogue), do: catalogue["piracy"]

  @doc "Raise at catalogue load, never on a tick, when the piracy model is malformed."
  def validate!(nil), do: nil

  def validate!(model) do
    campaign = model["campaign"] || %{}
    period = campaign["period_ms"]
    duration = campaign["duration_ms"]
    warning = campaign["warning_ms"]
    kinds = model["kinds"]

    valid =
      is_integer(model["seed"]) and is_integer(model["first_slot"]) and
        model["first_slot"] >= 0 and is_integer(period) and is_integer(duration) and
        is_integer(warning) and duration > 0 and warning >= 0 and warning + duration <= period and
        is_integer(campaign["multiplier"]) and campaign["multiplier"] >= 1 and is_map(kinds) and
        Enum.sort(Map.keys(kinds)) == @kinds and Enum.all?(kinds, fn {_, k} -> kind?(k) end) and
        is_map(model["zones"]) and map_size(model["zones"]) > 0 and
        Enum.all?(model["zones"], fn {_, z} -> zone?(z, kinds) end)

    unless valid,
      do: raise(ArgumentError, "Piracy must have bounded campaigns and well-formed zones")

    model
  end

  defp kind?(k),
    do:
      is_map(k) and is_binary(k["mark"]) and k["mark"] != "" and is_integer(k["hold_ms"]) and
        k["hold_ms"] > 0 and k["charge_bps"] in 0..10_000 and is_boolean(k["storm_suppressed"])

  defp zone?(z, kinds),
    do:
      is_map(z) and is_binary(z["name"]) and Map.has_key?(kinds, z["kind"]) and
        z["chance_bps"] in 0..10_000 and z["campaign_bps"] in 0..10_000 and
        z["guard_pct"] in 0..100 and is_list(z["campaign_names"]) and z["campaign_names"] != [] and
        Enum.all?(z["campaign_names"], &is_binary/1) and polygon?(z["polygon"]) and
        point?(z["label"])

  defp polygon?(ring), do: is_list(ring) and length(ring) >= 3 and Enum.all?(ring, &point?/1)

  defp point?([x, y]) when is_number(x) and is_number(y),
    do: x >= -180 and x <= 180 and y >= -90 and y <= 90

  defp point?(_), do: false

  @doc "Even-odd ray test in the longitude/latitude plane that voyage legs interpolate in."
  def inside?([x, y], ring) do
    ring
    |> Enum.zip(tl(ring) ++ [hd(ring)])
    |> Enum.reduce(false, fn {[x1, y1], [x2, y2]}, inside ->
      if y1 > y != y2 > y and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1),
        do: not inside,
        else: inside
    end)
  end

  @doc "The campaign a zone rolls for one period slot, or nil; its warning and run lie inside the slot."
  def campaign(zone_id, slot, model) do
    zone = model["zones"][zone_id]

    %{"period_ms" => period, "duration_ms" => duration, "warning_ms" => warning} =
      model["campaign"]

    seed = model["seed"]

    if zone && slot >= model["first_slot"] &&
         :erlang.phash2({seed, :campaign, zone_id, slot}, 10_000) < zone["campaign_bps"] do
      span = period - duration - warning
      offset = warning + :erlang.phash2({seed, :campaign_start, zone_id, slot}, span + 1)
      starts = slot * period + offset
      names = zone["campaign_names"]

      %{
        "id" => zone_id,
        "window_id" => "#{zone_id}:#{slot}",
        "name" =>
          Enum.at(names, :erlang.phash2({seed, :campaign_name, zone_id, slot}, length(names))),
        "announced_ms" => starts - warning,
        "starts_ms" => starts,
        "until_ms" => starts + duration
      }
    end
  end

  @doc "Campaigns announced or running at `now`, keyed by zone; at most one per zone."
  def campaigns(_now, nil), do: %{}

  def campaigns(now, model) do
    slot = div(max(0, now), model["campaign"]["period_ms"])

    for {id, _zone} <- model["zones"],
        c = campaign(id, slot, model),
        c != nil,
        c["announced_ms"] <= now,
        now < c["until_ms"],
        into: %{},
        do: {id, c}
  end

  @doc "Whether the pure seeded model has a campaign running in the zone at `at`."
  def campaign_active?(zone_id, at, model) do
    c = campaign(zone_id, div(max(0, at), model["campaign"]["period_ms"]), model)
    c != nil and c["starts_ms"] <= at and at < c["until_ms"]
  end

  @doc "A zone's published chance per crossing at `at`, before guards and hull."
  def chance_bps(zone_id, at, model) do
    base = model["zones"][zone_id]["chance_bps"]

    if campaign_active?(zone_id, at, model),
      do: min(10_000, base * model["campaign"]["multiplier"]),
      else: base
  end
end
