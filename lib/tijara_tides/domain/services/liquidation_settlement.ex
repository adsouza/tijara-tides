defmodule TijaraTides.Domain.Services.LiquidationSettlement do
  @moduledoc "Settle pool occupancy and sales without invoking liquidation orchestration."
  alias TijaraTides.Domain.{Warehouse, WarehouseWorld, CompanyFinanceWorld}
  alias TijaraTides.Domain.WarehouseLiquidationWorld, as: Pools
  defdelegate active?(state, id), to: Pools
  defdelegate pool(state, id), to: Pools
  defdelegate before_remove(state, id), to: Pools

  def refresh(state, id, catalogue) do
    if active?(state, id) do
      w = WarehouseWorld.fetch(state, id)

      blocks =
        div(
          Warehouse.volume(w, catalogue) + Warehouse.block_litres() - 1,
          Warehouse.block_litres()
        )

      state |> Pools.occupancy(id, blocks) |> WarehouseWorld.resize_expired(id, blocks)
    else
      state
    end
  end

  def record_sale(state, id, cargo, proceeds, handling \\ 0) do
    p = pool(state, id)
    cost = Enum.sum(for b <- cargo, do: b.quantity * b.unit_cost)

    state
    |> CompanyFinanceWorld.post(p["company_id"], "warehouse_liquidation_sale", [
      {"inventory", -cost},
      {"cost_of_goods", cost},
      {"sales_revenue", -proceeds},
      {"cash_reserved", proceeds}
    ])
    |> Pools.sale(id, proceeds, handling)
  end

  def take(state, id, good, n, catalogue, lot_ids \\ nil) do
    state = before_remove(state, id)
    {state, cargo} = WarehouseWorld.liquidation_out(state, id, good, n, lot_ids)
    {refresh(state, id, catalogue), cargo}
  end
end
