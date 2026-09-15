defmodule TijaraTides.Domain.PortCargoMarket.Rows do
  @moduledoc "Codec for the unchanged market row and its freshness batches."
  alias TijaraTides.Domain.PortCargoMarket
  alias TijaraTides.Domain.PortCargoMarket.Batch
  @fields ~w(port good merchant seller buyer stock demand budget batches last_production)a

  def decode(row) do
    unknown = Map.keys(row) -- Enum.map(@fields, &Atom.to_string/1)
    if unknown != [], do: raise(ArgumentError, "Unknown market fields: #{inspect(unknown)}")

    values = Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))})
    struct!(PortCargoMarket, %{values | batches: Enum.map(values.batches, &decode_batch/1)})
  end

  def encode(%PortCargoMarket{} = market) do
    Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(market, &1)})
    |> Map.put("batches", Enum.map(market.batches, &encode_batch/1))
  end

  defp decode_batch(row),
    do: %Batch{
      lot_id: Map.fetch!(row, "lot_id"),
      quantity: Map.fetch!(row, "quantity"),
      expires_ms: Map.fetch!(row, "expires_ms")
    }

  def encode_batch(%Batch{} = batch),
    do: %{
      "lot_id" => batch.lot_id,
      "quantity" => batch.quantity,
      "expires_ms" => batch.expires_ms
    }
end
