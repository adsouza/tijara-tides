defmodule TijaraTides.UseCases.DestinationMatrixCache do
  @moduledoc "One caller-owned destination matrix, reused only for identical planning inputs."
  alias TijaraTides.UseCases.{DestinationGeometryCache, GameQueries}

  def refresh(cache, definitions, view, ship, open) do
    if key = key(definitions, view, ship) do
      cond do
        cache && cache.key === key -> cache
        open -> elem(calculate(definitions, view, ship, nil), 0)
        true -> nil
      end
    end
  end

  def calculate(definitions, view, ship, geometry) do
    key = key(definitions, view, ship)
    {geometry, prepared} = DestinationGeometryCache.prepare(geometry, definitions)
    {%{key: key, matrix: GameQueries.destination_matrix(prepared, view, ship)}, geometry}
  end

  def key(definitions, view, ship) do
    if ship && view.private && ship["status"] in ["docked", "loading", "unloading"] do
      # Exact terms avoid hash collisions. Notices, locale and unrelated public
      # projections do not affect planning; all financial and fleet rows do.
      {
        definitions,
        view.public["clock_ms"],
        get_in(view.private, ["account", "id"]),
        Map.take(view.private, ["company", "ships", "ship_routes"]),
        view.markets,
        ship
      }
    end
  end
end
