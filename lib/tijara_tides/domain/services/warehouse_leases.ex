defmodule TijaraTides.Domain.Services.WarehouseLeases do
  @moduledoc "Coordinate each lease's term with expired-lease liquidation, in one tick or command."
  alias TijaraTides.Domain.{State, WarehouseWorld}
  alias TijaraTides.Domain.Services.WarehouseLiquidation

  @doc "The warehouse tick phase: term, liquidation preparation, spoilage, then sales."
  def advance(state, catalogue) do
    state = WarehouseWorld.synchronize(state)

    Enum.reduce(Enum.sort(Map.keys(State.entities(state, "warehouses"))), state, fn id, s ->
      if State.get(s, "warehouses", id), do: advance_lease(s, id, catalogue), else: s
    end)
  end

  defp advance_lease(state, id, catalogue) do
    state = WarehouseWorld.advance_term(state, id, catalogue)
    state = WarehouseLiquidation.prepare(state, WarehouseWorld.fetch(state, id), catalogue)
    state = WarehouseWorld.settle_term(state, id, catalogue)

    if State.get(state, "warehouses", id),
      do: WarehouseLiquidation.advance(state, id, catalogue),
      else: state
  end

  @doc "Replacement storage is priced against grace charges accrued up to the clock."
  def replace_award(state, account, command, lease_id, catalogue) do
    prepared =
      case WarehouseWorld.fetch(state, command["warehouse"]) do
        nil -> state
        w -> WarehouseLiquidation.prepare(state, w, catalogue)
      end

    WarehouseWorld.replace_award(prepared, account, command, lease_id, catalogue)
  end
end
