defmodule TijaraTides.Domain.VisitBudget do
  @moduledoc "Pure visit budget lifecycle and economic rules."
  @fields ~w(id company_id ship_id stop_id port amount remaining strict skip visit)a
  @enforce_keys @fields
  defstruct @fields

  def new(spec, amount, skip) do
    amount = amount || 0

    %__MODULE__{
      id: spec.id,
      company_id: spec.company_id,
      ship_id: spec.ship_id,
      stop_id: spec.stop_id,
      port: spec.port,
      amount: amount,
      remaining: amount,
      strict: spec.configured != nil,
      skip: skip,
      visit: spec.visit
    }
  end

  def resize(%__MODULE__{} = budget, amount, available, unpaid) do
    spent = budget.amount - budget.remaining
    delta = amount - budget.amount

    cond do
      amount < spent ->
        {:error, :visit_budget_committed}

      delta > available or (delta > 0 and unpaid > 0) ->
        {:error, :insufficient_cash}

      true ->
        {:ok,
         %{
           budget
           | amount: amount,
             remaining: budget.remaining + delta,
             strict: true,
             skip: false
         }, delta}
    end
  end

  def consume(%__MODULE__{} = budget, amount) do
    unless budget.strict and not budget.skip and amount <= budget.remaining,
      do: raise(ArgumentError, "Purchase exceeds reserved visit budget")

    %{budget | remaining: budget.remaining - amount}
  end
end
