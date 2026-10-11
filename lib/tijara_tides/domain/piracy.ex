defmodule TijaraTides.Domain.Piracy do
  @moduledoc "Pirate zones and deterministic announced campaigns in active-world time."

  @kinds ~w(boarding fleet_piracy militia piracy)
  # The seeded start offset hashes into span + 1; phash2 accepts ranges up to 2^32.
  @phash_range 4_294_967_296

  def model(catalogue), do: catalogue["piracy"]

  def kind_label("piracy"), do: "Held by pirates"
  def kind_label("fleet_piracy"), do: "Seized by a pirate fleet"
  def kind_label("boarding"), do: "Boarded and robbed"
  def kind_label("militia"), do: "Repairing strike damage"

  @doc "Validate the private attack salt at load time, separately from public zone definitions."
  def validate_salt!(model) do
    unless is_binary(model["salt"]) and byte_size(model["salt"]) >= 32,
      do: raise(ArgumentError, "Piracy requires a private salt of at least 32 bytes")

    model
  end

  @doc "Prepare an immutable index of catalogue paths; only geometry determines its contents."
  def prepare_crossings(nil, _routes), do: nil

  def prepare_crossings(model, routes) do
    model = Map.delete(model, :crossings)

    index =
      Map.new(routes, fn {_, route} ->
        {route["coordinates"], crossings(route, model)}
      end)

    Map.put(model, :crossings, {polygons(model), index})
  end

  @doc "Public and durable rules exclude private configuration and the derived geometry index."
  def public_model(model), do: Map.drop(model, ["salt", :crossings])

  defp polygons(model), do: Map.new(model["zones"], fn {id, zone} -> {id, zone["polygon"]} end)

  @doc "Partition the actual path, reusing prepared crossings only for the same path and polygons."
  def crossings(_route, nil), do: []

  def crossings(route, model) do
    case model[:crossings] do
      {geometry, index} ->
        if geometry == polygons(model) do
          case Map.fetch(index, route["coordinates"]) do
            {:ok, parts} -> parts
            :error -> calculate_crossings(route, model)
          end
        else
          calculate_crossings(route, model)
        end

      nil ->
        calculate_crossings(route, model)
    end
  end

  defp calculate_crossings(route, model) do
    alias TijaraTides.Domain.VoyageNavigation, as: Navigation

    legs =
      route["coordinates"]
      |> Enum.map(&Navigation.normalize/1)
      |> Enum.chunk_every(2, 1, :discard)

    total = Enum.sum(for [a, b] <- legs, do: Navigation.distance(a, b))

    {pieces, _} =
      Enum.reduce(legs, {[], 0.0}, fn [[x, y] = a, b], {pieces, walked} ->
        [dx, _] = Navigation.normalize([hd(b) - x, 0])
        dy = List.last(b) - y
        length = Navigation.distance(a, b)

        cuts =
          for {_, z} <- model["zones"],
              {p, q} <- Enum.zip(z["polygon"], tl(z["polygon"]) ++ [hd(z["polygon"])]),
              shift <- [-360, 0, 360],
              t = intersection([x, y], [dx, dy], p, q, shift),
              t != nil,
              do: t

        parts =
          [0.0, 1.0 | cuts]
          |> Enum.uniq()
          |> Enum.sort()
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.flat_map(fn [from, into] ->
            middle = (from + into) / 2

            for {id, z} <- Enum.sort(model["zones"]),
                total > 0 and inside?([x + dx * middle, y + dy * middle], z["polygon"]),
                do: {id, (walked + length * from) / total, (walked + length * into) / total}
          end)

        {pieces ++ parts, walked + length}
      end)

    Enum.reduce(pieces, [], fn
      {zone, from, into}, [{zone, previous, edge} | rest] when abs(from - edge) < 1.0e-10 ->
        [{zone, previous, into} | rest]

      part, acc ->
        [part | acc]
    end)
    |> Enum.reverse()
  end

  defp intersection([x, y], [dx, dy], [px, py], [qx, qy], shift) do
    ex = qx - px
    ey = qy - py
    determinant = dx * ey - dy * ex

    if abs(determinant) > 1.0e-12 do
      ax = px + shift - x
      ay = py - y
      t = (ax * ey - ay * ex) / determinant
      u = (ax * dy - ay * dx) / determinant
      if t > 0 and t < 1 and u >= 0 and u <= 1, do: t
    end
  end

  @doc "Snapshot crossings and private rolls; the salt never enters durable or visible state."
  def snapshot(route, model, ship_id, departure, previous \\ nil)
  def snapshot(_route, nil, _id, _departure, _previous), do: nil

  def snapshot(route, model, ship_id, departure, previous) do
    resolved = (previous && previous["resolved"]) || []
    first = (previous && previous["next_index"]) || 0
    parts = crossings(route, model)

    {pending, continued} =
      parts
      |> Enum.with_index(first)
      |> Enum.reduce({[], []}, fn {{zone, from, into}, index}, {pending, continued} ->
        if from < 1.0e-10 and Enum.any?(resolved, &(&1["zone"] == zone)) do
          {pending,
           continued ++
             [
               %{
                 "index" => index,
                 "zone" => zone,
                 "zone_name" => model["zones"][zone]["name"],
                 "mark" => model["kinds"][model["zones"][zone]["kind"]]["mark"],
                 "label" => kind_label(model["zones"][zone]["kind"]),
                 "outcome" => "continued",
                 "charge" => 0,
                 "recovery" => 0
               }
             ]}
        else
          fraction =
            from +
              (into - from) *
                ((:erlang.phash2(
                    {model["salt"], :attack_fraction, ship_id, departure, index},
                    1_000_000_000
                  ) + 1) / 1_000_000_001)

          crossing = %{
            "index" => index,
            "zone" => zone,
            "from_fraction" => from,
            "into_fraction" => into,
            "attack_fraction" => fraction,
            "roll" => :erlang.phash2({model["salt"], ship_id, departure, index}, 10_000)
          }

          {pending ++ [crossing], continued}
        end
      end)

    %{
      "model" => public_model(model),
      "protection" => (previous && previous["protection"]) || "none",
      "pending" => pending,
      "resolved" => resolved ++ continued,
      "incidents" => (previous && previous["incidents"]) || [],
      "next_index" => first + length(parts)
    }
  end

  @doc "The departure model; diversions retain the purchased voyage's public rules."
  def voyage_model(ship, catalogue) do
    current = model(catalogue)

    if get_in(ship, ["piracy", "model"]) do
      ship["piracy"]["model"]
      |> Map.put("salt", current["salt"])
      |> Map.put(:crossings, current[:crossings])
    else
      current
    end
  end

  def protection_settings(model),
    do:
      Map.merge(
        %{
          "guard_fee_bps" => 15,
          "loading_pct" => 140,
          "recovery_pct" => 80,
          "minimum_premium" => 2500
        },
        (model || %{})["protection"] || %{}
      )

  @doc "Safe public prices from private attack timing, with only currently announced campaigns."
  def protection_quotes(route, ship, departure, weather, model, previous \\ nil) do
    snapshot = snapshot(route, model, ship["id"], departure, previous)
    pending = (snapshot && snapshot["pending"]) || []
    crossing_quotes(pending, ship, departure, weather, model)
  end

  @doc "Price an already snapshotted set of crossings without deriving new private timings."
  def crossing_quotes(pending, ship, departure, weather, model) do
    class = TijaraTides.Domain.ShipClass.all()[ship["class"]]
    settings = protection_settings(model)

    Map.new(~w(none guards insurance both), fn choice ->
      guards = choice in ["guards", "both"]
      insured = choice in ["insurance", "both"]

      crossings =
        Enum.map(pending, fn crossing ->
          zone = model["zones"][crossing["zone"]]
          kind = model["kinds"][zone["kind"]]
          at = TijaraTides.Domain.Weather.time_at(weather, departure, crossing["attack_fraction"])

          campaign =
            campaign(crossing["zone"], div(max(0, at), model["campaign"]["period_ms"]), model)

          public_campaign = campaign && campaign["announced_ms"] <= departure

          quoted_model =
            if public_campaign, do: model, else: put_in(model, ["campaign", "multiplier"], 1)

          bps =
            if suppressed?(crossing, departure, weather, model),
              do: 0,
              else: attack_bps(crossing["zone"], at, quoted_model, class["speed"], guards)

          %{
            "zone" => crossing["zone"],
            "zone_name" => zone["name"],
            "kind" => zone["kind"],
            "label" => kind_label(zone["kind"]),
            "mark" => kind["mark"],
            "chance_bps" => bps,
            "charge" => div(class["price"] * kind["charge_bps"], 10_000)
          }
        end)

      expected =
        Enum.sum(
          for c <- crossings,
              do: div(c["chance_bps"] * c["charge"] * settings["recovery_pct"], 1_000_000)
        )

      fee =
        if guards,
          do:
            Enum.sum(
              for c <- pending,
                  do:
                    div(
                      class["price"] *
                        (model["zones"][c["zone"]]["guard_fee_ppm"] ||
                           settings["guard_fee_bps"] * 100),
                      1_000_000
                    )
            ),
          else: 0

      premium =
        if insured and pending != [],
          do: max(settings["minimum_premium"], div(expected * settings["loading_pct"], 100)),
          else: 0

      {choice,
       %{
         "protection" => choice,
         "crossings" => crossings,
         "guard_fee" => fee,
         "premium" => premium,
         "cost" => fee + premium,
         "recovery_pct" => settings["recovery_pct"],
         "insurance_available" => pending != []
       }}
    end)
  end

  @doc "Integer attack odds, with the campaign, guards and hull factors applied before the cap."
  def attack_bps(zone_id, at, model, speed, guards \\ false) do
    zone = model["zones"][zone_id]
    base = zone["chance_bps"]

    bps =
      if campaign_active?(zone_id, at, model),
        do: base * model["campaign"]["multiplier"],
        else: base

    bps = if guards, do: div(bps * (100 - zone["guard_pct"]), 100), else: bps
    bps = if model["kinds"][zone["kind"]]["storm_suppressed"], do: div(bps * 22, speed), else: bps
    min(10_000, bps)
  end

  @doc "Small boats are suppressed by any eligible storm between entry and the attack point."
  def suppressed?(crossing, departure, weather, model) do
    alias TijaraTides.Domain.Weather
    zone = model["zones"][crossing["zone"]]
    kind = model["kinds"][zone["kind"]]
    entry = Weather.time_at(weather, departure, crossing["from_fraction"])
    attack = Weather.time_at(weather, departure, crossing["attack_fraction"])

    segment =
      Enum.find(weather["segments"], fn [_, from, into] ->
        from <= crossing["attack_fraction"] and crossing["attack_fraction"] < into
      end)

    if kind["storm_suppressed"] and segment do
      [sector, _, _] = segment
      wmodel = weather["model"]

      first =
        max(
          wmodel["first_slot"],
          div(max(0, max(entry, weather["since_ms"])), wmodel["period_ms"])
        )

      last = div(max(0, attack), wmodel["period_ms"])

      last >= first and
        Enum.any?(first..last, fn slot ->
          w = Weather.window(sector, slot, wmodel)

          w != nil and w["starts_ms"] <= attack and
            w["until_ms"] > max(entry, weather["since_ms"])
        end)
    else
      false
    end
  end

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
        period - duration - warning < @phash_range and
        is_integer(campaign["multiplier"]) and campaign["multiplier"] >= 1 and is_map(kinds) and
        Enum.sort(Map.keys(kinds)) == @kinds and Enum.all?(kinds, fn {_, k} -> kind?(k) end) and
        is_map(model["zones"]) and map_size(model["zones"]) > 0 and
        Enum.all?(model["zones"], fn {_, z} -> zone?(z, kinds) end) and protection_valid?(model)

    unless valid,
      do: raise(ArgumentError, "Piracy must have bounded campaigns and well-formed zones")

    model
  end

  defp protection_valid?(model) do
    p = protection_settings(model)

    p["guard_fee_bps"] in 0..10_000 and p["recovery_pct"] in 0..100 and
      is_integer(p["loading_pct"]) and p["loading_pct"] >= 100 and p["loading_pct"] <= 1000 and
      is_integer(p["minimum_premium"]) and p["minimum_premium"] >= 0 and
      p["minimum_premium"] <= 1_000_000_000
  end

  defp kind?(k),
    do:
      is_map(k) and is_binary(k["mark"]) and k["mark"] != "" and is_integer(k["hold_ms"]) and
        k["hold_ms"] > 0 and k["hold_ms"] <= 86_400_000 and k["charge_bps"] in 0..10_000 and
        is_boolean(k["storm_suppressed"])

  defp zone?(z, kinds),
    do:
      is_map(z) and is_binary(z["name"]) and Map.has_key?(kinds, z["kind"]) and
        z["chance_bps"] in 0..10_000 and z["campaign_bps"] in 0..10_000 and
        z["guard_pct"] in 0..100 and
        (is_nil(z["guard_fee_ppm"]) or z["guard_fee_ppm"] in 0..1_000_000) and
        is_list(z["campaign_names"]) and z["campaign_names"] != [] and
        Enum.all?(z["campaign_names"], &is_binary/1) and polygon?(z["polygon"]) and
        point?(z["label"])

  defp polygon?(ring), do: is_list(ring) and length(ring) >= 3 and Enum.all?(ring, &point?/1)

  defp point?([x, y]) when is_number(x) and is_number(y),
    do: x >= -180 and x <= 180 and y >= -90 and y <= 90

  defp point?(_), do: false

  @doc """
  Even-odd ray test in the longitude/latitude plane. Route coordinates run past
  the antimeridian so legs interpolate across it; the point is wrapped first.
  """
  def inside?(point, ring) do
    [x, y] = TijaraTides.Domain.VoyageNavigation.normalize(point)

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
