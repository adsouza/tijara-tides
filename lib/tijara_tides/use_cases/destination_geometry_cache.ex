defmodule TijaraTides.UseCases.DestinationGeometryCache do
  @moduledoc "Caller-owned static path partitions, independent of planning time and prices."
  alias TijaraTides.Domain.{Piracy, Weather}

  def prepare(cache, definitions) do
    catalogue = definitions.catalogue
    routes = catalogue["routes"]
    paths = Map.new(routes, fn {id, route} -> {id, route["coordinates"]} end)
    model = catalogue["piracy"]
    polygons = model && Map.new(model["zones"], fn {id, zone} -> {id, zone["polygon"]} end)
    piracy_key = {paths, polygons}

    piracy =
      if cache && cache.piracy_key === piracy_key,
        do: cache.piracy,
        else: model && Piracy.prepare_crossings(model, routes)[:crossings]

    weather =
      if cache && cache.paths === paths,
        do: cache.weather,
        else: Weather.prepare_segments(routes)

    cache = %{paths: paths, piracy_key: piracy_key, piracy: piracy, weather: weather}

    catalogue =
      catalogue
      |> Map.put("piracy", model && Map.put(model, :crossings, piracy))
      |> Map.put("weather", Map.put(catalogue["weather"] || %{}, :segments, weather))

    {cache,
     definitions |> Map.put(:catalogue, catalogue) |> Map.put(:destination_geometry, cache)}
  end
end
