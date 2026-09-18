defmodule TijaraTides.Domain.CompanyFinanceTransitionTest do
  use ExUnit.Case, async: true

  alias TijaraTides.Domain.CompanyFinance
  alias TijaraTides.Domain.CompanyFinance.{OperatingBill, Transition}

  defp bill(id, remaining \\ 10),
    do: %OperatingBill{id: id, company_id: "company", due_ms: 100, remaining: remaining}

  defp transition(bills) do
    %CompanyFinance{id: "company", cash: 100, reserved: 0, unpaid: 0, profit: 0, bills: bills}
    |> Transition.new(100)
  end

  test "new children append in insertion order, including to an empty book" do
    first = bill("z")
    second = bill("a")
    third = bill("m")

    for initial <- [[], [first]] do
      state =
        transition(initial)
        |> Transition.put(:bills, second.id, second)
        |> Transition.put(:bills, third.id, third)

      assert Transition.finance(state).bills == initial ++ [second, third]

      assert MapSet.new(Transition.effects(state).children) ==
               MapSet.new([{:bills, second.id, :put, second}, {:bills, third.id, :put, third}])
    end
  end

  test "updating a child retains its position and putting it unchanged has no effects" do
    first = bill("z")
    middle = bill("a")
    last = bill("m")
    initial = transition([first, middle, last])

    unchanged = Transition.put(initial, :bills, middle.id, middle)
    assert Transition.finance(unchanged).bills == [first, middle, last]
    assert Transition.effects(unchanged).children == []

    updated = %{middle | remaining: 5}
    state = Transition.put(unchanged, :bills, updated.id, updated)
    assert Transition.finance(state).bills == [first, updated, last]
    assert Transition.get(state, :bills, updated.id) == updated
    assert Transition.effects(state).children == [{:bills, updated.id, :put, updated}]
  end

  test "deleting then reinserting a child appends it once and replaces its delete effect" do
    first = bill("z")
    middle = bill("a")
    last = bill("m")
    deleted = transition([first, middle, last]) |> Transition.delete(:bills, middle.id)

    assert Transition.finance(deleted).bills == [first, last]
    assert Transition.get(deleted, :bills, middle.id) == nil
    assert Transition.effects(deleted).children == [{:bills, middle.id, :delete, nil}]

    deleted_again = Transition.delete(deleted, :bills, middle.id)
    assert Transition.finance(deleted_again) == Transition.finance(deleted)
    assert Transition.effects(deleted_again) == Transition.effects(deleted)

    reinserted = Transition.put(deleted_again, :bills, middle.id, middle)
    assert Transition.finance(reinserted).bills == [first, last, middle]
    assert Transition.get(reinserted, :bills, middle.id) == middle
    assert Transition.effects(reinserted).children == [{:bills, middle.id, :put, middle}]
  end
end
