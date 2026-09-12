defmodule TijaraTides.Domain.CompanyFinance.Loan do
  @moduledoc "Typed financial child; decoding rejects missing or unknown persisted fields."
  @fields ~w(id company_id principal remaining principal_due interest_due interest_accrued interest_remainder interest_at_ms overdue_ms next_due_ms period_ms periods_left rate_bps installment status created_ms)a
  @enforce_keys @fields
  defstruct @fields ++ [guarantee_id: nil]

  @type t :: %__MODULE__{
          id: String.t(),
          guarantee_id: String.t() | nil,
          company_id: String.t(),
          principal: integer(),
          remaining: integer(),
          principal_due: integer(),
          interest_due: integer(),
          interest_accrued: integer(),
          interest_remainder: integer(),
          interest_at_ms: integer(),
          overdue_ms: integer() | nil,
          next_due_ms: integer(),
          period_ms: integer(),
          periods_left: integer(),
          rate_bps: integer(),
          installment: integer(),
          status: String.t(),
          created_ms: integer()
        }
  def from_row(nil), do: nil
  def from_row(%__MODULE__{} = child), do: child

  def from_row(row) do
    unknown = Map.keys(row) -- ["guarantee_id" | Enum.map(@fields, &Atom.to_string/1)]
    if unknown != [], do: raise(ArgumentError, "Unknown loan fields: #{inspect(unknown)}")

    struct!(
      __MODULE__,
      Map.put(
        Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))}),
        :guarantee_id,
        row["guarantee_id"]
      )
    )
  end

  def to_row(%__MODULE__{} = child),
    do: Map.new([:guarantee_id | @fields], &{Atom.to_string(&1), Map.fetch!(child, &1)})
end
