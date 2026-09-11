defmodule TijaraTides.Domain.ScopedChangesTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{State, EntityIndex, ReadState, ChangeSet}

  test "ownership index follows creation transfer removal and cache eviction" do
    state = EntityIndex.rebuild(%{entities: %{}, clock_ms: 0})
    a = %{"id" => "s", "company_id" => "a"}
    state = State.put(state, "ships", "s", a)
    assert ReadState.owned(state, "ships", "company_id", "a") == [a]
    moved = State.put(state, "ships", "s", %{a | "company_id" => "b"})
    assert ReadState.owned(moved, "ships", "company_id", "a") == []
    assert ChangeSet.affected_companies(state, moved) == ["a", "b"]
    deleted = State.delete(moved, "ships", "s")
    assert ReadState.owned(deleted, "ships", "company_id", "b") == []
    evicted = State.evict(moved, "ships", "s")
    assert evicted.entity_index == %{}
    assert ChangeSet.since(moved, evicted) == %{}
  end

  test "reconciliation includes journal-only changes and former owners of deleted rows" do
    before = %{entities: %{"loans" => %{"l" => %{"company_id" => "a"}}}}
    changed = State.delete(before, "loans", "l")
    changed = Map.put(changed, :journal, [%{company: "b"}])
    assert ChangeSet.affected_companies(before, changed) == ["a", "b"]
  end
end
