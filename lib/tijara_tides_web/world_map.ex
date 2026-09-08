defmodule TijaraTidesWeb.WorldMap do
  @moduledoc "Equal Earth projection and antimeridian splitting for public map geometry."

  # Equal Earth forward equations; see the source attribution in priv/game/NOTICE.md.
  def project([longitude, latitude]) do
    radians = :math.pi() / 180
    m = :math.sqrt(3) / 2
    theta = :math.asin(m * :math.sin(latitude * radians))
    t2 = theta * theta
    t6 = t2 * t2 * t2

    px =
      longitude * radians * :math.cos(theta) /
        (m * (1.340264 - 3 * 0.081106 * t2 + t6 * (7 * 0.000893 + 9 * 0.003796 * t2)))

    py = theta * (1.340264 - 0.081106 * t2 + t6 * (0.000893 + 0.003796 * t2))
    [500 + 177 * px, 250 - 177 * py]
  end

  def regions(catalogue) do
    clustered = catalogue["clusters"] |> Map.values() |> List.flatten()

    groups =
      Map.to_list(catalogue["clusters"]) ++
        for name <- Map.keys(catalogue["ports"]), name not in clustered, do: {name, [name]}

    groups
    |> Enum.map(fn {name, ports} ->
      points = Enum.map(ports, &project(catalogue["ports"][&1]["coordinates"]))

      center = [
        Enum.sum(Enum.map(points, &hd/1)) / length(points),
        Enum.sum(Enum.map(points, &List.last/1)) / length(points)
      ]

      %{name: name, ports: Enum.sort(ports), center: center}
    end)
    |> Enum.sort_by(& &1.name)
  end

  def viewport(_catalogue, nil), do: %{box: "0 0 1000 500", scale: 1.0}

  def viewport(catalogue, region) do
    points =
      Enum.map(catalogue["clusters"][region], &project(catalogue["ports"][&1]["coordinates"]))

    xs = Enum.map(points, &hd/1)
    ys = Enum.map(points, &List.last/1)
    width = max(40, max((Enum.max(xs) - Enum.min(xs)) * 1.6, (Enum.max(ys) - Enum.min(ys)) * 3.2))
    height = width
    x = (Enum.min(xs) + Enum.max(xs) - width) / 2
    y = (Enum.min(ys) + Enum.max(ys) - height) / 2
    %{box: "#{x} #{y} #{width} #{height}", scale: width / 1000}
  end

  def markers(catalogue, nil), do: regions(catalogue)

  def markers(catalogue, region) do
    for name <- Enum.sort(catalogue["clusters"][region]),
        do: %{name: name, ports: [name], center: project(catalogue["ports"][name]["coordinates"])}
  end

  # Place close delta labels on different sides of their harbor markers.
  def label_position("Guangzhou"), do: %{dx: -11, dy: -8, anchor: "end"}
  def label_position("Hong Kong"), do: %{dx: 0, dy: 21, anchor: "middle"}
  def label_position("Antwerp"), do: %{dx: -11, dy: 18, anchor: "end"}
  def label_position("Rotterdam"), do: %{dx: -11, dy: -8, anchor: "end"}
  def label_position("Abu Dhabi"), do: %{dx: -11, dy: 18, anchor: "end"}
  def label_position(_name), do: %{dx: 11, dy: 4, anchor: "start"}

  def normalize([lon, lat]), do: [lon - 360 * :math.floor((lon + 180) / 360), lat]

  def segments(coords) do
    coords
    |> Enum.map(&normalize/1)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [[a, b], [c, d]] ->
      delta = c - a

      if abs(delta) > 180 do
        adjusted = if delta > 180, do: c - 360, else: c + 360
        edge = if adjusted > a, do: 180, else: -180
        latitude = b + (d - b) * (edge - a) / (adjusted - a)
        [[[a, b], [edge, latitude]], [[-edge, latitude], [c, d]]]
      else
        [[[a, b], [c, d]]]
      end
    end)
  end

  def points(coords),
    do:
      Enum.map_join(coords, " ", fn point ->
        [x, y] = project(point)
        "#{x},#{y}"
      end)

  def path(coords) do
    segments(coords)
    |> Enum.map_join(" ", fn [a, b] -> "M" <> points(interpolate(a, b)) end)
  end

  def route_arrows(coords, scale) do
    spacing = 80 * scale

    legs =
      coords
      |> segments()
      |> Enum.flat_map(fn [a, b] -> interpolate(a, b) |> Enum.chunk_every(2, 1, :discard) end)

    total =
      Enum.reduce(legs, 0, fn [a, b], sum ->
        [x, y] = project(a)
        [u, v] = project(b)
        sum + :math.sqrt((u - x) * (u - x) + (v - y) * (v - y))
      end)

    {_remaining, arrows} =
      legs
      |> Enum.reduce({min(spacing / 2, total / 2), []}, fn [a, b], {remaining, arrows} ->
        [x, y] = project(a)
        [u, v] = project(b)
        dx = u - x
        dy = v - y
        length = :math.sqrt(dx * dx + dy * dy)

        if length == 0 or length < remaining do
          {remaining - length, arrows}
        else
          count = floor((length - remaining) / spacing) + 1
          angle = :math.atan2(dy, dx) * 180 / :math.pi()

          added =
            for i <- 0..(count - 1) do
              fraction = (remaining + i * spacing) / length
              %{x: x + dx * fraction, y: y + dy * fraction, angle: angle}
            end

          {remaining + count * spacing - length, arrows ++ added}
        end
      end)

    arrows
  end

  defp interpolate([a, b], [c, d]) do
    steps = max(1, ceil(max(abs(c - a), abs(d - b)) / 2))
    for i <- 0..steps, do: [a + (c - a) * i / steps, b + (d - b) * i / steps]
  end
end
