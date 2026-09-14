defmodule TijaraTides.Domain.PortCargoMarket.Lots do
  @moduledoc "Scoped clock and lot allocation value; contains no world entities."
  alias TijaraTides.Domain.PortCargoMarket.Batch
  @enforce_keys [:clock_ms]
  defstruct [:clock_ms, lot_allocation: {:local, 1}, new_lots: []]

  def create(%__MODULE__{} = lots, good, quantity, expires, parent \\ nil) do
    {lots, row} = TijaraTides.Domain.CargoLots.create(lots, good, quantity, expires, parent)
    {lots, %Batch{lot_id: row["lot_id"], quantity: quantity, expires_ms: expires}}
  end

  def take(%__MODULE__{} = lots, batches, quantity, good) do
    {lots, taken, left, 0} =
      Enum.reduce(batches, {lots, [], [], quantity}, fn %Batch{} = batch,
                                                        {lots, taken, left, need} ->
        amount = min(need, batch.quantity)

        cond do
          amount == 0 ->
            {lots, taken, left ++ [batch], need}

          amount == batch.quantity ->
            {lots, taken ++ [batch], left, need - amount}

          true ->
            {lots, part} = create(lots, good, amount, batch.expires_ms, batch.lot_id)

            {lots, rest} =
              create(lots, good, batch.quantity - amount, batch.expires_ms, batch.lot_id)

            {lots, taken ++ [part], left ++ [rest], need - amount}
        end
      end)

    {lots, taken, left}
  end
end
