defmodule TijaraTides.Domain.Ship.CargoBatch do
  @moduledoc "A quantity of one cargo lot owned by a ship, with immutable cost and expiry."
  @enforce_keys [:good, :quantity]
  defstruct [:good, :quantity, :lot_id, :expires_ms, unit_cost: 0]

  @type t :: %__MODULE__{
          good: String.t(),
          quantity: pos_integer(),
          lot_id: String.t() | nil,
          expires_ms: non_neg_integer() | nil,
          unit_cost: non_neg_integer()
        }
  def take(state, batches, quantity, good) do
    {state, sold, kept, 0} =
      Enum.reduce(batches, {state, [], [], quantity}, fn %__MODULE__{} = batch,
                                                         {state, sold, kept, needed} ->
        amount = if batch.good == good, do: min(needed, batch.quantity), else: 0

        cond do
          amount == 0 ->
            {state, sold, kept ++ [batch], needed}

          amount == batch.quantity ->
            {state, sold ++ [batch], kept, needed - amount}

          true ->
            {state, part} =
              TijaraTides.Domain.CargoLots.create(
                state,
                good,
                amount,
                batch.expires_ms,
                batch.lot_id
              )

            {state, rest} =
              TijaraTides.Domain.CargoLots.create(
                state,
                good,
                batch.quantity - amount,
                batch.expires_ms,
                batch.lot_id
              )

            {state, sold ++ [%{batch | lot_id: part["lot_id"], quantity: amount}],
             kept ++ [%{batch | lot_id: rest["lot_id"], quantity: batch.quantity - amount}],
             needed - amount}
        end
      end)

    {state, sold, kept}
  end
end
