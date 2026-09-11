defmodule TijaraTides.Domain.Ship.QuantityPolicy do
  @moduledoc "A route's fixed-load or maximum-feasible intent, independent of a visit's fill progress."
  @enforce_keys [:mode]
  defstruct [:mode, :lots]

  def from_target(%{"quantity_mode" => "maximum"}), do: %__MODULE__{mode: :maximum}
  def from_target(target), do: %__MODULE__{mode: :fixed, lots: target["quantity"]}

  def resolve(%__MODULE__{mode: :maximum}, "buy", _aboard, free_capacity),
    do: max(0, free_capacity)

  def resolve(%__MODULE__{mode: :maximum}, "sell", aboard, _), do: aboard
  def resolve(%__MODULE__{mode: :fixed, lots: lots}, "buy", aboard, _), do: max(0, lots - aboard)
  def resolve(%__MODULE__{mode: :fixed, lots: lots}, "sell", aboard, _), do: min(lots, aboard)
end
