defmodule TijaraTides.Domain.Markets do
  @moduledoc "Compatibility facade; each market is owned by PortCargoMarket."
  defdelegate quote(state, catalogue, port, good), to: TijaraTides.Domain.PortCargoMarket
  defdelegate raw_goods(), to: TijaraTides.Domain.PortCargoMarket
  defdelegate handling_rate(port), to: TijaraTides.Domain.PortCargoMarket
  defdelegate initialize(state, catalogue), to: TijaraTides.Domain.PortCargoMarket
  defdelegate advance(state, catalogue), to: TijaraTides.Domain.PortCargoMarket
end
