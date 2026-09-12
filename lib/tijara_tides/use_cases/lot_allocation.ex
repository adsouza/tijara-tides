defmodule TijaraTides.UseCases.LotAllocation do
  @moduledoc "Supplies identities to pure operations; retries only before any persistence effects."
  def run(game, {store, storage}, operation) do
    ids =
      case Map.get(game, :lot_allocation, []) do
        ids when is_list(ids) -> ids
        {:local, _} -> []
      end

    attempt(game, store, storage, operation, ids)
  end

  defp attempt(game, store, storage, operation, ids) do
    try do
      operation.(Map.put(game, :lot_allocation, ids))
    rescue
      TijaraTides.Domain.LotIdsExhausted ->
        more = store.allocate_lot_ids(storage, max(64, length(ids)))
        attempt(game, store, storage, operation, ids ++ more)
    end
  end
end
