defmodule TijaraTides.Domain.CompanyFinanceAggregateTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.CompanyFinance, as: Finance

  defp company do
    %{"id" => "c", "cash" => 1000, "reserved" => 0, "unpaid" => 0, "profit" => 0}
  end

  test "reserving cash prevents a later purchase from spending it" do
    finance = Finance.from_row(company())
    reserved = Finance.apply_entries(finance, [{"cash_reserved", 800}, {"cash_available", -800}])
    assert reserved.cash == 1000
    assert Finance.available(reserved) == 200

    assert_raise ArgumentError, fn ->
      Finance.apply_entries(reserved, [{"inventory", 201}, {"cash_available", -201}])
    end

    assert_raise ArgumentError, fn ->
      Finance.apply_entries(reserved, [{"fuel_expense", 801}, {"cash_reserved", -801}])
    end

    assert Finance.apply_entries(reserved, [{"inventory", 200}, {"cash_available", -200}]).cash ==
             800
  end

  test "financial balances and journal use the same entries; borrowing is not profit" do
    state = %{clock_ms: 10, entities: %{"companies" => %{"c" => company()}}}
    entries = [{"cash_available", 500}, {"loan_principal", -500}]
    state = Finance.post(state, "c", "loan_draw", entries)
    assert state.entities["companies"]["c"]["cash"] == 1500
    assert state.entities["companies"]["c"]["profit"] == 0
    assert hd(state.journal).entries == entries
    assert_raise ArgumentError, fn -> Finance.post(state, "c", "bad", [{"cash_available", 1}]) end

    assert_raise ArgumentError, fn ->
      Finance.apply_entries(Finance.from_row(company()), [{"payables", 1}, {"cash_available", -1}])
    end
  end

  test "crew creates arrears while reserved fuel remains available only for fuel" do
    row = %{company() | "reserved" => 900}
    state = %{clock_ms: 20, entities: %{"companies" => %{"c" => row}}}

    state =
      Finance.ship_operations(state, "c", "ship", %{
        fuel: 300,
        crew: 200,
        depreciation: 0,
        spoilage: 0
      })

    assert %{
             "cash" => 600,
             "reserved" => 600,
             "unpaid" => 100,
             "profit" => -500,
             "unpaid_since" => 20
           } = state.entities["companies"]["c"]

    assert Finance.from_world(state, "c").bills |> hd() |> Map.fetch!("remaining") == 100
  end

  test "loaded finance settles without accounts or ships and emits a receivership effect" do
    row =
      Map.merge(company(), %{
        "cash" => 0,
        "unpaid" => 100,
        "account_id" => "a",
        "bankruptcy_ms" => nil,
        "unpaid_since" => 0,
        "arrears_since" => 0
      })

    root = %{
      Finance.from_row(row)
      | bills: [%{"id" => "b", "company_id" => "c", "due_ms" => 0, "remaining" => 100}]
    }

    {next, effects} = Finance.settle_finances(root, Finance.terms().grace_ms)
    assert effects.receivership
    assert next.unpaid == 100
    assert next.details["bankruptcy_ms"] == nil
    assert Enum.map(next.bills, & &1["id"]) == ["b"]
  end
end
