defmodule TijaraTides.Domain.CargoLots do
  @moduledoc "Permanent world-scoped identities and split lineage, independent of FIFO position."

  def create(state, good, quantity, expires, parent \\ nil) do
    number = Map.get(state, :next_lot_id, 1)
    id = "lot:#{number}"

    record = %{
      "id" => id,
      "good" => good,
      "quantity" => quantity,
      "expires_ms" => expires,
      "parent_lot_id" => parent,
      "created_ms" => state.clock_ms
    }

    state =
      state
      |> Map.put(:next_lot_id, number + 1)
      |> Map.update(:new_lots, [record], &(&1 ++ [record]))

    {state, %{"lot_id" => id, "quantity" => quantity, "expires_ms" => expires}}
  end

  def take(state, batches, quantity, good) do
    {state, taken, left, 0} =
      Enum.reduce(batches, {state, [], [], quantity}, fn batch, {state, taken, left, need} ->
        amount =
          if Map.get(batch, "good", good) == good, do: min(need, batch["quantity"]), else: 0

        cond do
          amount == 0 ->
            {state, taken, left ++ [batch], need}

          amount == batch["quantity"] ->
            {state, taken ++ [batch], left, need - amount}

          true ->
            {state, part} = create(state, good, amount, batch["expires_ms"], batch["lot_id"])

            {state, rest} =
              create(
                state,
                good,
                batch["quantity"] - amount,
                batch["expires_ms"],
                batch["lot_id"]
              )

            {state, taken ++ [Map.merge(batch, part)], left ++ [Map.merge(batch, rest)],
             need - amount}
        end
      end)

    {state, taken, left}
  end
end
