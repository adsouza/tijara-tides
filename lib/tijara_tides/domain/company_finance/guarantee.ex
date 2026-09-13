defmodule TijaraTides.Domain.CompanyFinance.Guarantee do
  @moduledoc "Typed financial child with bounded settlement transitions."
  @fields ~w(id company_id sponsor_id beneficiary_id borrower_company_id amount forfeited status created_ms)a
  @enforce_keys @fields
  defstruct @fields
  @type t :: %__MODULE__{}
  def from_row(nil), do: nil
  def from_row(%__MODULE__{} = child), do: validate!(child)

  def from_row(row) do
    unknown = Map.keys(row) -- Enum.map(@fields, &Atom.to_string/1)
    if unknown != [], do: raise(ArgumentError, "Unknown guarantee fields: #{inspect(unknown)}")

    struct!(__MODULE__, Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))}))
    |> validate!()
  end

  def to_row(%__MODULE__{} = child) do
    validate!(child)
    Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(child, &1)})
  end

  defp validate!(child) do
    unless child.status in ["pledged", "claimed", "released"] and is_integer(child.amount) and
             child.amount > 0 and is_integer(child.forfeited) and child.forfeited >= 0 and
             child.forfeited <= child.amount,
           do: raise(ArgumentError, "Invalid guarantee")

    child
  end

  def settle(%__MODULE__{} = pledge, loss) do
    unless pledge.status == "pledged" and is_integer(loss) and loss >= 0 and loss <= pledge.amount,
      do: raise(ArgumentError, "Invalid guarantee settlement")

    %{pledge | status: if(loss > 0, do: "claimed", else: "released"), forfeited: loss}
  end
end
