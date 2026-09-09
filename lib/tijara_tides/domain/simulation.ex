defmodule TijaraTides.Domain.Simulation do
  @moduledoc "World-clock choreography; every phase belongs to its domain and commits together."
  alias TijaraTides.Domain.{Accounts, Fleet, Markets, Notices}

  def initialize(state, catalogue),
    do: state |> Notices.prune_notices() |> Markets.initialize(catalogue)

  def advance(state, elapsed, catalogue) when is_integer(elapsed) and elapsed >= 0 do
    %{state | clock_ms: state.clock_ms + elapsed}
    |> Fleet.advance(elapsed)
    |> Markets.advance(catalogue)
    |> TijaraTides.Domain.ShipInstructions.advance(catalogue)
    |> Accounts.expire_invitations()
  end
end
