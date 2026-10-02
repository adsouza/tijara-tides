defmodule TijaraTides.Domain.RemoteLink.Rows do
  @moduledoc "Closed codec for the existing durable remote link row."
  alias TijaraTides.Domain.RemoteLink

  @fields ~w(id company_id ship_id stop_id good warehouse_id port order_id generation filled status)a
  def decode(row) do
    keys = Enum.map(@fields, &Atom.to_string/1)
    unless Map.keys(row) -- keys == [], do: raise(ArgumentError, "Unknown remote_link fields")
    struct!(RemoteLink, Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))}))
  end

  def encode(%RemoteLink{} = model),
    do: Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(model, &1)})
end
