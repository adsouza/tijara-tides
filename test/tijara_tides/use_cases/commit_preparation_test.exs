defmodule TijaraTides.UseCases.CommitPreparationTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.Journal
  alias TijaraTides.UseCases.CommitPreparation

  test "a new company's multiple journal entries establish capital exactly once" do
    before = %{clock_ms: 0, entities: %{}}

    changed =
      before
      |> TijaraTides.Domain.State.put("companies", "c", %{"cash" => 3000})
      |> Journal.post("c", "capital", [{"cash_available", 1000}, {"capital", -1000}])
      |> Journal.post("c", "capital", [{"cash_available", 2000}, {"capital", -2000}])

    prepared = CommitPreparation.prepare(before, changed)
    assert prepared.entities["reporting_accounts"]["c"]["capital"] == 3000
    assert CommitPreparation.prepare(before, changed) == prepared
  end

  test "market versions distinguish unchanged, updated, inserted and deleted rows" do
    alias TijaraTides.Domain.State

    before = %{
      clock_ms: 0,
      entities: %{
        "markets" => %{"same" => %{stock: 1}, "updated" => %{stock: 1}, "deleted" => %{stock: 1}}
      },
      market_versions: %{"same" => 7, "updated" => 4, "deleted" => 9}
    }

    changed =
      before
      |> State.put("markets", "same", %{stock: 1})
      |> State.put("markets", "updated", %{stock: 2})
      |> State.put("markets", "inserted", %{stock: 1})
      |> State.delete("markets", "deleted")

    assert CommitPreparation.prepare(before, changed).market_versions ==
             %{"same" => 7, "updated" => 5, "inserted" => 0}
  end

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
