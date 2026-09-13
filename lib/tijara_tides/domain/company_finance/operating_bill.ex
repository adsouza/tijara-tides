defmodule TijaraTides.Domain.CompanyFinance.OperatingBill do
  @moduledoc "Typed financial child with bounded settlement transitions."
  @fields ~w(id company_id due_ms remaining)a
  @enforce_keys @fields
  defstruct @fields
  @type t :: %__MODULE__{}
  def from_row(nil), do: nil
  def from_row(%__MODULE__{} = child), do: validate!(child)

  def from_row(row) do
    unknown = Map.keys(row) -- Enum.map(@fields, &Atom.to_string/1)

    if unknown != [],
      do: raise(ArgumentError, "Unknown operating_bill fields: #{inspect(unknown)}")

    struct!(__MODULE__, Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))}))
    |> validate!()
  end

  def to_row(%__MODULE__{} = child) do
    validate!(child)
    Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(child, &1)})
  end

  defp validate!(child) do
    unless is_integer(child.due_ms) and child.due_ms >= 0 and is_integer(child.remaining) and
             child.remaining >= 0,
           do: raise(ArgumentError, "Invalid operating_bill")

    child
  end

  def pay(%__MODULE__{} = bill, amount) do
    unless is_integer(amount) and amount >= 0 and amount <= bill.remaining,
      do: raise(ArgumentError, "Payment exceeds operating bill")

    %{bill | remaining: bill.remaining - amount}
  end
end
