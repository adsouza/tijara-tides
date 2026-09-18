defmodule TijaraTides.Domain.Simulation do
  alias TijaraTides.Domain.AccountWorld
  alias TijaraTides.Domain.PortCargoMarketWorld
  @moduledoc "World-clock choreography; every phase belongs to its domain and commits together."
  alias TijaraTides.Domain.{Fleet, Notices}

  def initialize(state, catalogue),
    do:
      state
      |> Notices.prune_notices()
      |> PortCargoMarketWorld.initialize(catalogue)
      |> TijaraTides.Domain.MerchantWarehouseWorld.advance(catalogue)

  def advance(state, elapsed, catalogue),
    do: advance(state, elapsed, catalogue, fn _phase, fun -> fun.() end)

  # The application may time phases; the default remains a pure transition.
  def advance(state, elapsed, catalogue, measure) when is_integer(elapsed) and elapsed >= 0 do
    phases = [
      finance_before: &TijaraTides.Domain.Services.FinancialSettlement.settle/1,
      fleet: &Fleet.advance(&1, elapsed),
      exchange_reconcile: &TijaraTides.Domain.Services.Exchange.reconcile/1,
      estates: &TijaraTides.Domain.Services.Estates.advance(&1, catalogue),
      auctions: &TijaraTides.Domain.Services.Auctions.advance(&1, catalogue),
      merchant_warehouses: &TijaraTides.Domain.MerchantWarehouseWorld.advance(&1, catalogue),
      warehouses: &TijaraTides.Domain.WarehouseWorld.advance(&1, catalogue),
      finance_after: &TijaraTides.Domain.Services.FinancialSettlement.settle/1,
      markets: &PortCargoMarketWorld.advance(&1, catalogue),
      exchange: &TijaraTides.Domain.Services.Exchange.advance(&1, catalogue),
      berths: &TijaraTides.Domain.Services.BerthAllocation.advance(&1, catalogue),
      automated_visits: &TijaraTides.Domain.Services.AutomatedVisits.advance(&1, catalogue),
      release_berths: &TijaraTides.Domain.Services.BerthAllocation.release_idle(&1, catalogue),
      expire_invitations: &AccountWorld.expire_invitations/1
    ]

    Enum.reduce(phases, %{state | clock_ms: state.clock_ms + elapsed}, fn {phase, transition},
                                                                          current ->
      measure.(phase, fn -> transition.(current) end)
    end)
  end
end
