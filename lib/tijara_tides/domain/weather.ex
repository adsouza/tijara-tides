defmodule TijaraTides.Domain.Weather do
  @moduledoc "Deterministic regional weather and distance-based voyage pauses in active-world time."
  alias TijaraTides.Domain.VoyageNavigation, as: Navigation

  @defaults %{
    "period_ms" => 1_800_000,
    "duration_ms" => 60_000,
    "chance_bps" => 1000,
    "first_slot" => 1,
    "seed" => 1729,
    "stagger" => true
  }

  def model(catalogue), do: Map.merge(@defaults, catalogue["weather"] || %{})

  def region([longitude, latitude]) do
    [longitude, _] = Navigation.normalize([longitude, latitude])
    x = min(5, max(0, floor((longitude + 180) / 60)))
    y = min(3, max(0, floor((latitude + 90) / 45)))
    "sector:" <> Integer.to_string(y * 6 + x)
  end

  def window(region, slot, model) do
    period = model["period_ms"]
    duration = model["duration_ms"]

    unless is_integer(period) and period >= 10_000 and is_integer(duration) and
             duration > 0 and duration <= div(period, 4) and model["chance_bps"] in 0..10_000 and
             is_integer(model["first_slot"]) and model["first_slot"] >= 0 and
             is_integer(model["seed"]) and is_boolean(model["stagger"]),
           do: raise(ArgumentError, "Weather must have a bounded storm and a clear interval")

    hash = :erlang.phash2({model["seed"], region, slot}, 1_000_000_000)

    if slot >= model["first_slot"] and rem(hash, 10_000) < model["chance_bps"] do
      # Scale an independent hash to the entire available interval. Dividing the
      # chance hash first restricted starts to the first 100 seconds of a window.
      offset =
        if model["stagger"] do
          start_hash = :erlang.phash2({:storm_start, model["seed"], region, slot}, 1_000_000_000)
          div(start_hash * (period - duration), 1_000_000_000)
        else
          0
        end

      start = slot * period + offset

      %{
        "id" => region,
        "window_id" => "#{region}:#{slot}",
        "starts_ms" => start,
        "until_ms" => start + duration
      }
    end
  end

  def active(now, model) do
    slot = div(max(0, now), model["period_ms"])

    for id <- 0..23,
        w = window("sector:" <> Integer.to_string(id), slot, model),
        w != nil,
        w["starts_ms"] <= now,
        now < w["until_ms"],
        into: %{},
        do: {w["id"], w}
  end

  @doc "Only storms already announced by cutoff can revise the current forecast."
  def forecast(route, sailing_ms, departure, cutoff, model, since \\ nil) do
    since = since || departure

    skip =
      cutoff < model["first_slot"] * model["period_ms"] or
        (departure == cutoff and map_size(active(cutoff, model)) == 0)

    {holds, _finish} =
      Enum.reduce(
        if(not skip and is_list(route["coordinates"]) and length(route["coordinates"]) >= 2,
          do: segments(route),
          else: []
        ),
        {[], departure},
        fn {sector, from, into}, {holds, cursor} ->
          move = max(0, round(into * sailing_ms) - round(from * sailing_ms))
          cross(sector, move, cursor, cutoff, model, since, holds)
        end
      )

    %{
      "sailing_ms" => sailing_ms,
      "model" => model,
      "since_ms" => since,
      "holds" => holds,
      "delay_ms" => Enum.sum(for h <- holds, do: h["until_ms"] - h["starts_ms"])
    }
  end

  defp cross(_sector, 0, cursor, _cutoff, _model, _since, holds), do: {holds, cursor}

  defp cross(sector, move, cursor, cutoff, model, since, holds) do
    period = model["period_ms"]
    first = div(max(0, max(cursor, since)), period)
    last = div(max(0, min(cursor + move, cutoff)), period)

    storm =
      if last >= first do
        Enum.find_value(first..last, fn slot ->
          w = window(sector, slot, model)

          if w && w["starts_ms"] <= cutoff && w["until_ms"] > max(cursor, since) &&
               max(w["starts_ms"], since) < cursor + move,
             do: w
        end)
      end

    if storm do
      start = max(since, max(cursor, storm["starts_ms"]))
      hold = Map.put(storm, "starts_ms", start)

      cross(
        sector,
        move - (start - cursor),
        storm["until_ms"],
        cutoff,
        model,
        since,
        holds ++ [hold]
      )
    else
      {holds, cursor + move}
    end
  end

  @doc "Partition the actual sea path at regional boundaries, including dateline crossings."
  def segments(route) do
    legs =
      route["coordinates"]
      |> Enum.map(&Navigation.normalize/1)
      |> Enum.chunk_every(2, 1, :discard)

    total = Enum.sum(Enum.map(legs, fn [a, b] -> Navigation.distance(a, b) end))

    if total <= 0 do
      [{region(hd(route["coordinates"])), 0.0, 1.0}]
    else
      {pieces, _} =
        Enum.reduce(legs, {[], 0.0}, fn [[x, y] = a, b], {pieces, walked} ->
          [dx, _] = Navigation.normalize([hd(b) - x, 0])
          dy = List.last(b) - y
          length = Navigation.distance(a, b)
          cuts = [0.0, 1.0] ++ cuts(x, dx, -360..360//60) ++ cuts(y, dy, -90..90//45)

          parts =
            cuts
            |> Enum.uniq()
            |> Enum.sort()
            |> Enum.chunk_every(2, 1, :discard)
            |> Enum.map(fn [from, into] ->
              middle = (from + into) / 2

              {region([x + dx * middle, y + dy * middle]), (walked + length * from) / total,
               (walked + length * into) / total}
            end)

          {pieces ++ parts, walked + length}
        end)

      # Joining adjacent same-region pieces keeps the per-voyage timeline small.
      Enum.reduce(pieces, [], fn
        {sector, _from, into}, [{sector, previous, _} | rest] -> [{sector, previous, into} | rest]
        part, acc -> [part | acc]
      end)
      |> Enum.reverse()
    end
  end

  defp cuts(_origin, delta, _boundaries) when delta == 0, do: []

  defp cuts(origin, delta, boundaries),
    do: for(edge <- boundaries, t = (edge - origin) / delta, t > 0 and t < 1, do: t)

  def duration(departure, arrival, nil), do: max(1, arrival - departure)
  def duration(_departure, _arrival, weather), do: weather["sailing_ms"]

  def motion(departure, arrival, weather, now) do
    duration = duration(departure, arrival, weather)
    paused = paused(weather, departure, now)
    min(duration, max(0, now - departure - paused))
  end

  def paused(nil, _from, _into), do: 0

  def paused(weather, from, into),
    do:
      Enum.sum(
        for h <- weather["holds"],
            do: max(0, min(into, h["until_ms"]) - max(from, h["starts_ms"]))
      )

  def current(weather, now),
    do: weather && Enum.find(weather["holds"], &(&1["starts_ms"] <= now and now < &1["until_ms"]))
end
