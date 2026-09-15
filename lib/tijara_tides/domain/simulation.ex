defmodule TijaraTides.Domain.Simulation do
  alias TijaraTides.Domain.PortCargoMarketWorld
  @moduledoc "World-clock choreography; every phase belongs to its domain and commits together."
  alias TijaraTides.Domain.{Account, Fleet, Notices}

  def initialize(state, catalogue),
    do:
      state
      |> Notices.prune_notices()
      |> PortCargoMarketWorld.initialize(catalogue)

  def advance(state, elapsed, catalogue) when is_integer(elapsed) and elapsed >= 0 do
    %{state | clock_ms: state.clock_ms + elapsed}
    |> TijaraTides.Domain.Services.FinancialSettlement.settle()
    |> Fleet.advance(elapsed)
    |> TijaraTides.Domain.Services.Exchange.reconcile()
    |> TijaraTides.Domain.Services.Auctions.advance(catalogue)
    |> TijaraTides.Domain.WarehouseWorld.advance(catalogue)
    |> TijaraTides.Domain.Services.FinancialSettlement.settle()
    |> PortCargoMarketWorld.advance(catalogue)
    |> TijaraTides.Domain.Services.Exchange.advance(catalogue)
    |> TijaraTides.Domain.Services.BerthAllocation.advance(catalogue)
    |> TijaraTides.Domain.Services.AutomatedVisits.advance(catalogue)
    |> TijaraTides.Domain.Services.BerthAllocation.release_idle(catalogue)
    |> Account.expire_invitations()
  end
end
