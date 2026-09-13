defmodule TijaraTides.Domain.VoyageNavigation do
  @moduledoc "Diversions use existing sea-network edges and a split of the ship's current edge."
  def normalize([x, y]), do: [x - 360 * :math.floor((x + 180) / 360), y * 1.0]

  def distance([x, y], [a, b]) do
    r = :math.pi() / 180

    h =
      :math.sin((b - y) * r / 2) ** 2 +
        :math.cos(y * r) * :math.cos(b * r) * :math.sin((a - x) * r / 2) ** 2

    3440.065 * 2 * :math.asin(:math.sqrt(min(1.0, h)))
  end

  def path(ship, catalogue),
    do:
      ship["voyage_path"] ||
        get_in(catalogue, ["routes", ship["port"] <> "|" <> ship["destination"], "coordinates"])

  def split(ship, clock, catalogue) do
    coords = path(ship, catalogue) |> Enum.map(&normalize/1)
    legs = Enum.chunk_every(coords, 2, 1, :discard)

    target =
      Enum.sum(Enum.map(legs, fn [a, b] -> distance(a, b) end)) *
        min(
          1,
          max(0, (clock - ship["depart_ms"]) / max(1, ship["arrive_ms"] - ship["depart_ms"]))
        )

    Enum.reduce_while(
      legs,
      {List.last(coords), List.last(coords), List.last(coords), target},
      fn [a, b], {_, _, _, left} ->
        length = distance(a, b)

        if left <= length and length > 0 do
          [x, y] = a
          [dx, _] = normalize([hd(b) - x, 0])
          point = normalize([x + dx * left / length, y + (List.last(b) - y) * left / length])
          {:halt, {point, a, b, 0}}
        else
          {:cont, {b, a, b, left - length}}
        end
      end
    )
  end

  def reroute(ship, clock, destination, catalogue) do
    if ship["status"] == "sailing" and is_list(path(ship, catalogue)) and
         destination != ship["destination"] and
         catalogue["ports"][destination] do
      {point, a, b, _} = split(ship, clock, catalogue)

      graph =
        Enum.reduce(catalogue["routes"], %{}, fn {_, route}, g ->
          Enum.reduce(Enum.chunk_every(route["coordinates"], 2, 1, :discard), g, fn [x, y], g ->
            edge(g, normalize(x), normalize(y))
          end)
        end)

      # Include earlier diversions so another change of course still starts exactly here.
      graph =
        Enum.reduce(Enum.chunk_every(path(ship, catalogue), 2, 1, :discard), graph, fn [x, y],
                                                                                       g ->
          edge(g, normalize(x), normalize(y))
        end)

      graph = graph |> edge(point, a) |> edge(point, b)
      finish = normalize(catalogue["ports"][destination]["coordinates"])

      case search(graph, :gb_sets.singleton({0.0, point}), %{point => 0.0}, %{}, finish) do
        nil ->
          nil

        {length, previous} ->
          coords = unwind(previous, finish, [])

          passages =
            Enum.filter(catalogue["canal_edges"] || [], fn e ->
              Enum.any?(Enum.chunk_every(coords, 2, 1, :discard), fn [x, y] ->
                (x == normalize(e["from"]) and y == normalize(e["to"])) or
                  (y == normalize(e["from"]) and x == normalize(e["to"]))
              end)
            end)
            |> Enum.map(& &1["passage"])
            |> Enum.uniq()

          %{
            "coordinates" => coords,
            "nautical_miles" => max(1, round(length)),
            "passages" => passages
          }
      end
    end
  end

  defp edge(g, a, a), do: g

  defp edge(g, a, b) do
    length = distance(a, b)

    g
    |> Map.update(a, %{b => length}, &Map.put(&1, b, length))
    |> Map.update(b, %{a => length}, &Map.put(&1, a, length))
  end

  defp search(g, queue, dist, prev, finish) do
    if :gb_sets.is_empty(queue), do: nil, else: search_next(g, queue, dist, prev, finish)
  end

  defp search_next(g, queue, dist, prev, finish) do
    {{cost, node}, queue} = :gb_sets.take_smallest(queue)

    cond do
      cost > dist[node] ->
        search(g, queue, dist, prev, finish)

      node == finish ->
        {cost, prev}

      true ->
        {queue, dist, prev} =
          Enum.reduce(Map.get(g, node, %{}), {queue, dist, prev}, fn {next, length}, {q, d, p} ->
            value = cost + length

            if not Map.has_key?(d, next) or value < d[next],
              do:
                {:gb_sets.add({value, next}, q), Map.put(d, next, value), Map.put(p, next, node)},
              else: {q, d, p}
          end)

        search(g, queue, dist, prev, finish)
    end
  end

  defp unwind(previous, node, path) do
    case previous[node] do
      nil -> [node | path]
      prior -> unwind(previous, prior, [node | path])
    end
  end
end
