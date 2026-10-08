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
      |> TijaraTides.Domain.PiracyWorld.refresh(catalogue)
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
      piracy: &TijaraTides.Domain.PiracyWorld.refresh(&1, catalogue),
      fleet: &Fleet.advance(&1, elapsed),
      instruction_expiry:
        &TijaraTides.Domain.Services.DepartureFunding.expire_instructions(&1, catalogue),
      route_waits:
        &TijaraTides.Domain.Services.DepartureFunding.expire_route_waits(&1, catalogue),
      linked_orders: &TijaraTides.Domain.Services.LinkedOrders.advance(&1, catalogue),
      estates: &TijaraTides.Domain.Services.Estates.advance(&1, catalogue),
      auctions: &TijaraTides.Domain.Services.Auctions.advance(&1, catalogue),
      merchant_warehouses: &TijaraTides.Domain.MerchantWarehouseWorld.advance(&1, catalogue),
      warehouses: &TijaraTides.Domain.Services.WarehouseLeases.advance(&1, catalogue),
      # After warehouse pruning, so orders follow pruned claims; before finance, so
      # expired buy orders return their cash before payments are taken.
      exchange_reconcile: &TijaraTides.Domain.Services.Exchange.reconcile/1,
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
    |> settled(state, catalogue)
  end

  # Test builds verify that the tick's transitions released what they invalidated.
  @settled_check Application.compile_env(:tijara_tides, :settled_check)

  if @settled_check do
    defp settled(changed, before, catalogue),
      do: apply(@settled_check, :assert_settled!, [before, changed, catalogue, "tick"])
  else
    defp settled(changed, _before, _catalogue), do: changed
  end
end
