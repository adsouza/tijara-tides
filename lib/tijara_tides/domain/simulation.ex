defmodule TijaraTides.Domain.Simulation do
  @moduledoc "World-clock choreography; every phase belongs to its domain and commits together."
  alias TijaraTides.Domain.{Account, Fleet, PortCargoMarket, Notices, Ship}

  def initialize(state, catalogue),
    do:
      state
      |> Notices.prune_notices()
      |> PortCargoMarket.initialize(catalogue)

  def advance(state, elapsed, catalogue) when is_integer(elapsed) and elapsed >= 0 do
    %{state | clock_ms: state.clock_ms + elapsed}
    |> TijaraTides.Domain.CompanyFinance.settle()
    |> Fleet.advance(elapsed)
    |> TijaraTides.Domain.CompanyFinance.settle()
    |> PortCargoMarket.advance(catalogue)
    |> Ship.execute_visits(catalogue)
    |> Account.expire_invitations()
  end
end
