defmodule TijaraTides.Domain.Account.Dormancy do
  @moduledoc "Owner absence and advance notice use explicit wall-clock timestamps."
  @fields ~w(id company_id account_id last_visit_ms warned_ms closes_ms closed_ms guarantee_id guaranteed_debt)a
  defstruct @fields
  @defaults %{"absence_ms" => 30 * 86_400_000, "warning_ms" => 7 * 86_400_000}

  def settings(catalogue) do
    settings = Map.merge(@defaults, catalogue["dormancy"] || %{})

    unless Enum.all?(~w(absence_ms warning_ms), &(is_integer(settings[&1]) and settings[&1] > 0)),
      do: raise(ArgumentError, "Invalid dormancy settings")

    settings
  end

  def new(company, account, now),
    do: %__MODULE__{
      id: company,
      company_id: company,
      account_id: account,
      last_visit_ms: now,
      guaranteed_debt: 0
    }

  def visit(%__MODULE__{closed_ms: nil} = record, now),
    do: %{record | last_visit_ms: max(record.last_visit_ms, now), warned_ms: nil, closes_ms: nil}

  def visit(record, _now), do: record

  def warn(%__MODULE__{warned_ms: nil, closed_ms: nil} = record, now, settings) do
    if now >= record.last_visit_ms + settings["absence_ms"],
      do: %{record | warned_ms: now, closes_ms: now + settings["warning_ms"]},
      else: record
  end

  def warn(record, _now, _settings), do: record

  def due?(record, now),
    do: record.closed_ms == nil and record.closes_ms != nil and now >= record.closes_ms

  def from_row(row),
    do: struct!(__MODULE__, Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))}))

  def to_row(record), do: Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(record, &1)})
end
