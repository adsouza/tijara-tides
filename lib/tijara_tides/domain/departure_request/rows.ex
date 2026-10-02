defmodule TijaraTides.Domain.DepartureRequest.Rows do
  @moduledoc "Closed codec for the existing durable departure request row."
  alias TijaraTides.Domain.DepartureRequest

  @fields ~w(id ship_id company_id destination stop_id visit configured policy required blocked_ms accumulated window_deadline_ms cooldown_ms)a
  def decode(row) do
    keys = Enum.map(@fields, &Atom.to_string/1)

    unless Map.keys(row) -- keys == [],
      do: raise(ArgumentError, "Unknown departure_request fields")

    struct!(DepartureRequest, Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))}))
  end

  def encode(%DepartureRequest{} = model),
    do: Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(model, &1)})
end
