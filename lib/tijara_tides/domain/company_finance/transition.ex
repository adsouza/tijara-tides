defmodule TijaraTides.Domain.CompanyFinance.Transition do
  @moduledoc "Typed, company-scoped working state and explicit financial effects; no world rows."
  defstruct [
    :finance,
    :clock_ms,
    journal: [],
    notices: %{},
    changes: %{},
    children: %{},
    order: %{},
    sequence: 0
  ]

  @children [:loans, :installments, :bills, :pledges]

  def new(finance, now) do
    rows = Map.new(@children, fn kind -> {kind, Map.fetch!(finance, kind)} end)

    %__MODULE__{
      finance: finance,
      clock_ms: now,
      children: Map.new(rows, fn {kind, list} -> {kind, Map.new(list, &{&1.id, &1})} end),
      order:
        Map.new(rows, fn {kind, list} ->
          {kind, Map.new(Enum.with_index(list), fn {child, index} -> {child.id, index} end)}
        end),
      sequence: Enum.sum(Enum.map(Map.values(rows), &length/1))
    }
  end

  # Callers read the open book; closed loans stay addressable through the adapter.
  def finance(t) do
    finance =
      Enum.reduce(@children, t.finance, fn kind, finance ->
        children = Map.fetch!(t.children, kind)

        rows =
          Map.fetch!(t.order, kind)
          |> Enum.sort_by(fn {_id, position} -> position end)
          |> Enum.map(fn {id, _position} -> Map.fetch!(children, id) end)

        Map.put(finance, kind, rows)
      end)

    %{finance | loans: Enum.filter(finance.loans, &(&1.status == "open"))}
  end

  def effects(t),
    do: %{
      journal: t.journal,
      notices: Map.to_list(t.notices),
      children: Enum.map(t.changes, fn {{kind, id}, {op, child}} -> {kind, id, op, child} end)
    }

  def get(t, :company, id), do: if(t.finance.id == id, do: t.finance)

  def get(t, kind, id) when kind in @children,
    do: Map.get(Map.fetch!(t.children, kind), id)

  def entities(t, kind) when kind in @children,
    do: Map.fetch!(t.children, kind)

  def owned(t, kind, :company_id, id) when kind in @children,
    do: Enum.filter(Map.values(Map.fetch!(t.children, kind)), &(&1.company_id == id))

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
      # A row holds the position it was first given. One deleted and added again
      # takes a fresh position at the end, as rebuilding the list used to do.
      fresh = not Map.has_key?(Map.fetch!(t.children, kind), id)

      %{
        t
        | children: Map.update!(t.children, kind, &Map.put(&1, id, child)),
          order:
            if(fresh,
              do: Map.update!(t.order, kind, &Map.put(&1, id, t.sequence)),
              else: t.order
            ),
          sequence: if(fresh, do: t.sequence + 1, else: t.sequence),
          changes: Map.put(t.changes, {kind, id}, {:put, child})
      }
    end
  end

  def delete(t, kind, id) when kind in @children do
    if get(t, kind, id) do
      %{
        t
        | children: Map.update!(t.children, kind, &Map.delete(&1, id)),
          order: Map.update!(t.order, kind, &Map.delete(&1, id)),
          changes: Map.put(t.changes, {kind, id}, {:delete, nil})
      }
    else
      t
    end
  end
end
