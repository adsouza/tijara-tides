defmodule TijaraTides.Domain.Capacity do
  @moduledoc "Occupied cargo capacity, measured in kilograms and litres."
  defstruct weight: 0, volume: 0
  @type t :: %__MODULE__{weight: non_neg_integer(), volume: non_neg_integer()}
end
