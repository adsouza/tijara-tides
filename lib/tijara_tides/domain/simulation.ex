defmodule TijaraTides.Domain.Simulation do
  @moduledoc "World-clock choreography; every phase belongs to its domain and commits together."
  alias TijaraTides.Domain.{Account, Fleet, PortCargoMarket, Notices}

  def initialize(state, catalogue),
    do:
      state
      |> Notices.prune_notices()
      |> PortCargoMarket.initialize(catalogue)

  def advance(state, elapsed, catalogue) when is_integer(elapsed) and elapsed >= 0 do
    %{state | clock_ms: state.clock_ms + elapsed}
    |> TijaraTides.Domain.Services.FinancialSettlement.settle()
    |> Fleet.advance(elapsed)
    |> TijaraTides.Domain.Warehouse.advance(catalogue)
    |> TijaraTides.Domain.Services.FinancialSettlement.settle()
    |> PortCargoMarket.advance(catalogue)
    |> TijaraTides.Domain.Services.BerthAllocation.advance(catalogue)
    |> TijaraTides.Domain.Services.AutomatedVisits.advance(catalogue)
    |> TijaraTides.Domain.Services.BerthAllocation.release_idle(catalogue)
    |> Account.expire_invitations()
  end
end
