defmodule TijaraTides.Domain.ChangeSetTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{State, ChangeSet, Reporting}

  test "record latest operation only and distinguish earlier accepted work" do
    before = %{entities: %{}, clock_ms: 0}
    created = State.put(before, "notices", "n", %{"text" => "one"})
    assert ChangeSet.since(before, created) == %{{"notices", "n"} => :put}
    assert State.put(created, "notices", "n", %{"text" => "one"}) == created
    deleted = State.delete(created, "notices", "n")
    assert ChangeSet.since(before, deleted) == %{{"notices", "n"} => :delete}
    accepted = ChangeSet.accepted(deleted)
    next = State.put(accepted, "notices", "other", %{})
    assert ChangeSet.since(accepted, next) == %{{"notices", "other"} => :put}
  end

  test "report eviction does not delete durable history but explicit removal does" do
    row = %{"id" => "old", "period" => "quarter", "period_index" => 0}

    before = %{
      entities: %{"financial_reports" => %{"old" => row}},
      clock_ms: Reporting.duration("quarter")
    }

    compacted = Reporting.compact(before)
    assert compacted.entities["financial_reports"] == %{}
    assert ChangeSet.since(before, compacted) == %{}

    assert ChangeSet.since(before, State.delete(before, "financial_reports", "old")) == %{
             {"financial_reports", "old"} => :delete
           }
  end
end
