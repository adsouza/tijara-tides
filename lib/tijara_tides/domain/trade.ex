defmodule TijaraTides.Domain.Trade do
  @moduledoc "A manual trade intention; ownership, feasibility and prices are revalidated at execution."
  @enforce_keys [:side, :ship_id, :good, :quantity, :limit]
  defstruct [:side, :ship_id, :good, :quantity, :limit, :destination]

  @type t :: %__MODULE__{
          side: String.t(),
          ship_id: String.t(),
          good: String.t(),
          quantity: integer(),
          limit: integer(),
          destination: String.t() | nil
        }
end
