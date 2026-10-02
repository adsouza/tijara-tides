defmodule TijaraTides.Domain.Simulation do
  alias TijaraTides.Domain.AccountWorld
  alias TijaraTides.Domain.PortCargoMarketWorld
  @moduledoc "World-clock choreography; every phase belongs to its domain and commits together."
  alias TijaraTides.Domain.{Fleet, Notices}

  def initialize(state, catalogue),
    do:
      state
      |> Notices.prune_notices()
      |> TijaraTides.Domain.WeatherWorld.refresh(catalogue)
      |> PortCargoMarketWorld.initialize(catalogue)
      |> TijaraTides.Domain.MerchantWarehouseWorld.advance(catalogue)

  def advance(state, elapsed, catalogue),
    do: advance(state, elapsed, catalogue, fn _phase, fun -> fun.() end)

  # The application may time phases; the default remains a pure transition.
  def advance(state, elapsed, catalogue, measure) when is_integer(elapsed) and elapsed >= 0 do
    phases = [
      finance_before: &TijaraTides.Domain.Services.FinancialSettlement.settle/1,
      weather:
        &TijaraTides.Domain.Services.WeatherDelays.advance(
          &1,
          elapsed,
          catalogue,
          Fleet.voyage_speedup()
        ),
      fleet: &Fleet.advance(&1, elapsed),
      instruction_expiry:
        &TijaraTides.Domain.Services.DepartureFunding.expire_instructions(&1, catalogue),
      route_waits:
        &TijaraTides.Domain.Services.DepartureFunding.expire_route_waits(&1, catalogue),
      linked_orders: &TijaraTides.Domain.Services.LinkedOrders.advance(&1, catalogue),
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

    changed =
      Enum.reduce(phases, %{state | clock_ms: state.clock_ms + elapsed}, fn {phase, transition},
                                                                            current ->
        measure.(phase, fn -> transition.(current) end)
      end)

    measure.(:invitation_accrual, fn ->
      TijaraTides.Domain.AccountWorld.InvitationAccrual.observe(state, changed, catalogue, :all)
    end)
  end
end
