defmodule TijaraTides.UseCases.DestinationMatrixCache do
  @moduledoc "One caller-owned destination matrix, reused only for identical planning inputs."
  alias TijaraTides.UseCases.GameQueries

  def refresh(cache, definitions, view, ship, open) do
    if ship && view.private && ship["status"] in ["docked", "loading", "unloading"] do
      # Exact terms avoid hash collisions. Notices, locale and unrelated public
      # projections do not affect planning; all financial and fleet rows do.
      key = {
        definitions,
        view.public["clock_ms"],
        get_in(view.private, ["account", "id"]),
        Map.take(view.private, ["company", "ships", "ship_routes"]),
        view.markets,
        ship
      }

      cond do
        cache && cache.key === key -> cache
        open -> %{key: key, matrix: GameQueries.destination_matrix(definitions, view, ship)}
        true -> nil
      end
    end
  end
end
