defmodule TijaraTides.Domain.WarehouseLiquidationWorld do
  @moduledoc "Hydrate liquidation pools and store named pure model transitions."
  alias TijaraTides.Domain.{State, Warehouse, LiquidationPool}
  alias LiquidationPool.Rows
  defdelegate terms(catalogue), to: LiquidationPool
  def pool(state, id), do: State.get(state, "warehouse_liquidations", id)

  defp fetch(state, id) do
    case pool(state, id) do
      nil -> nil
      row -> Rows.decode(row)
    end
  end

  def active?(state, id), do: LiquidationPool.active?(fetch(state, id))

  def prepare(state, w, catalogue) do
    company = State.get(state, "companies", w.company_id)

    if state.clock_ms >= w.expires_ms and
         (company["bankruptcy_ms"] == nil or active?(state, w.id)) do
      state =
        if pool(state, w.id),
          do: state,
          else:
            put(
              state,
              LiquidationPool.new(
                w,
                div(
                  Warehouse.volume(w, catalogue) + Warehouse.block_litres() - 1,
                  Warehouse.block_litres()
                ),
                TijaraTides.Domain.PortCargoMarket.handling_rate(catalogue["ports"][w.port])
              )
            )

      before_remove(state, w.id)
    else
      state
    end
  end

  def before_remove(state, id) do
    case fetch(state, id) do
      nil -> state
      model -> put(state, LiquidationPool.accrue(model, state.clock_ms))
    end
  end

  def occupancy(state, id, blocks),
    do: put(state, LiquidationPool.occupancy(fetch(state, id), blocks))

  def clearance_value(state, id, good, numerator, denominator) do
    {model, value} =
      LiquidationPool.clearance_value(fetch(state, id), good, numerator, denominator)

    {put(state, model), value}
  end

  def sale(state, id, proceeds, handling),
    do: put(state, LiquidationPool.sale(fetch(state, id), proceeds, handling))

  def begin(state, id), do: put(state, LiquidationPool.begin(fetch(state, id), state.clock_ms))

  def complete(state, id, charges, net, estate),
    do:
      put(state, LiquidationPool.complete(fetch(state, id), charges, net, estate, state.clock_ms))

  def replace(state, id, charges),
    do: put(state, LiquidationPool.replace(fetch(state, id), charges, state.clock_ms))

  defp put(state, model),
    do: State.put(state, "warehouse_liquidations", model.id, Rows.encode(model))
end
