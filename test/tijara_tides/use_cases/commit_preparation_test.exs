defmodule TijaraTides.UseCases.CommitPreparationTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.Journal
  alias TijaraTides.UseCases.CommitPreparation

  test "journal only records events; preparation applies them once and acceptance discards history from memory" do
    before = %{clock_ms: 0, entities: %{"companies" => %{"c" => %{"cash" => 0}}}}
    changed = put_in(before, [:entities, "companies", "c", "cash"], 10_000)

    changed =
      Journal.post(changed, "c", "capital", [{"cash_available", 10_000}, {"capital", -10_000}])

    refute Map.has_key?(changed.entities, "reporting_accounts")
    prepared = CommitPreparation.prepare(before, changed)
    assert prepared.entities["reporting_accounts"]["c"]["capital"] == 10_000
    assert prepared == CommitPreparation.prepare(before, changed)
    accepted = CommitPreparation.accepted(prepared)
    refute Map.has_key?(accepted, :journal)
    advanced = CommitPreparation.prepare(accepted, %{accepted | clock_ms: 604_800_001})

    assert advanced.entities["financial_reports"]["c:quarter:0"]["capital_ms"] ==
             604_800_000 * 10_000

    compact = CommitPreparation.accepted(advanced)
    refute Map.has_key?(compact.entities["financial_reports"], "c:quarter:0")
    assert Map.has_key?(compact.entities["financial_reports"], "c:quarter:1")
    assert Map.has_key?(compact.entities["financial_reports"], "c:year:0")
  end
end
