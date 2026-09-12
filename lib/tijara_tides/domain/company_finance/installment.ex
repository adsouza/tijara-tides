defmodule TijaraTides.Domain.CompanyFinance.Installment do
  @moduledoc "Typed financial child; decoding rejects missing or unknown persisted fields."
  @fields ~w(id company_id loan_id due_ms principal_due interest_due)a
  @enforce_keys @fields
  defstruct @fields

  @type t :: %__MODULE__{
          id: String.t(),
          company_id: String.t(),
          loan_id: String.t(),
          due_ms: integer(),
          principal_due: integer(),
          interest_due: integer()
        }
  def from_row(nil), do: nil
  def from_row(%__MODULE__{} = child), do: child

  def from_row(row) do
    unknown = Map.keys(row) -- Enum.map(@fields, &Atom.to_string/1)
    if unknown != [], do: raise(ArgumentError, "Unknown installment fields: #{inspect(unknown)}")
    struct!(__MODULE__, Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))}))
  end

  def to_row(%__MODULE__{} = child),
    do: Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(child, &1)})
end
