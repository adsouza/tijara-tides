defmodule TijaraTides.Domain.CompanyFinance.Transition do
  @moduledoc "Typed, company-scoped working state and explicit financial effects; no world rows."
  defstruct [:finance, :clock_ms, journal: [], notices: %{}, changes: %{}]
  @children [:loans, :installments, :bills, :pledges]

  def new(finance, now), do: %__MODULE__{finance: finance, clock_ms: now}
  def finance(t), do: %{t.finance | loans: Enum.filter(t.finance.loans, &(&1.status == "open"))}

  def effects(t),
    do: %{
      journal: t.journal,
      notices: Map.to_list(t.notices),
      children: Enum.map(t.changes, fn {{kind, id}, {op, child}} -> {kind, id, op, child} end)
    }

  def get(t, :company, id), do: if(t.finance.id == id, do: t.finance)

  def get(t, kind, id) when kind in @children,
    do: Enum.find(Map.fetch!(t.finance, kind), &(&1.id == id))

  def entities(t, kind) when kind in @children,
    do: Map.new(Map.fetch!(t.finance, kind), &{&1.id, &1})

  def owned(t, kind, :company_id, id) when kind in @children,
    do: Enum.filter(Map.fetch!(t.finance, kind), &(&1.company_id == id))

  def put(t, :company, id, finance) do
    unless id == t.finance.id and finance.id == id,
      do: raise(ArgumentError, "Foreign financial owner")

    %{t | finance: finance}
  end

  def put(t, kind, id, child) when kind in @children do
    unless child.id == id and child.company_id == t.finance.id,
      do: raise(ArgumentError, "Foreign financial child")

    if get(t, kind, id) == child do
      t
    else
      children = Enum.reject(Map.fetch!(t.finance, kind), &(&1.id == id)) ++ [child]

      %{
        t
        | finance: Map.put(t.finance, kind, children),
          changes: Map.put(t.changes, {kind, id}, {:put, child})
      }
    end
  end

  def delete(t, kind, id) when kind in @children do
    if get(t, kind, id) do
      children = Enum.reject(Map.fetch!(t.finance, kind), &(&1.id == id))

      %{
        t
        | finance: Map.put(t.finance, kind, children),
          changes: Map.put(t.changes, {kind, id}, {:delete, nil})
      }
    else
      t
    end
  end
end
