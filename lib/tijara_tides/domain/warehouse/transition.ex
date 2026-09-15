defmodule TijaraTides.Domain.Warehouse.Transition do
  @moduledoc "An updated warehouse and explicit child writes; omitted children never imply deletion."
  @enforce_keys [:warehouse]
  defstruct [:warehouse, put: [], delete: []]
end
