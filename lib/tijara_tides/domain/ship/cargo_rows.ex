defmodule TijaraTides.Domain.Ship.CargoRows do
  @moduledoc "Cargo row codec shared by existing world adapters."
  alias TijaraTides.Domain.Ship.CargoBatch
  @fields ~w(good quantity lot_id expires_ms unit_cost)a

  @doc "Accept either representation where a collection's element type is not known."
  def coerce(%CargoBatch{} = batch), do: batch
  def coerce(row), do: decode(row)

  def decode(row) do
    unknown = Map.keys(row) -- Enum.map(@fields, &Atom.to_string/1)
    if unknown != [], do: raise(ArgumentError, "Unknown cargo batch fields: #{inspect(unknown)}")

    batch =
      struct!(
        CargoBatch,
        Map.new(row, fn {key, value} -> {String.to_existing_atom(key), value} end)
      )

    unless is_binary(batch.good) and is_integer(batch.quantity) and batch.quantity > 0 and
             is_integer(batch.unit_cost) and batch.unit_cost >= 0 and
             (batch.expires_ms == nil or is_integer(batch.expires_ms)),
           do: raise(ArgumentError, "Invalid cargo batch")

    batch
  end

  def encode(%CargoBatch{} = batch),
    do: Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(batch, &1)})
end
