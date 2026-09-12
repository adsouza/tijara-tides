defmodule TijaraTides.Domain.CompanyFinanceAggregateTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.Services.{FinancialSettlement}
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
    assert next.bankruptcy_ms == nil
    assert Enum.map(next.bills, & &1["id"]) == ["b"]
  end

  for ownership <- [:missing, :detached, :reassigned] do
    test "foreclosure cannot affect another company when the owner is #{ownership}" do
      overdue =
        Map.merge(company(), %{
          "cash" => 0,
          "unpaid" => 100,
          "account_id" => "a",
          "bankruptcy_ms" => nil,
          "unpaid_since" => 0,
          "arrears_since" => 0
        })

      current =
        Map.merge(company(), %{"id" => "current", "account_id" => "a", "bankruptcy_ms" => nil})

      account = %{
        "id" => "a",
        "company_id" => if(unquote(ownership) == :reassigned, do: "current"),
        "bankruptcies" => 0
      }

      accounts = if unquote(ownership) == :missing, do: %{}, else: %{"a" => account}

      state = %{
        clock_ms: Finance.terms().grace_ms,
        entities: %{
          "companies" => %{"c" => overdue, "current" => current},
          "accounts" => accounts,
          "operating_bills" => %{
            "b" => %{"id" => "b", "company_id" => "c", "due_ms" => 0, "remaining" => 100}
          }
        }
      }

      assert {_, %{receivership: true}} = Finance.settle_owned(state, "c")
      next = FinancialSettlement.settle(state, ["c"])
      assert next.entities["companies"]["current"] == current
      assert next.entities["accounts"] == accounts
      assert next.entities["companies"]["c"]["bankruptcy_ms"] == nil
      assert next.entities["operating_bills"]["b"]["remaining"] == 100
      assert Map.get(next.entities, "bankruptcy_events", %{}) == %{}
    end
  end

  test "an omitted child is not a deletion, while paying a loaded bill explicitly removes it" do
    row =
      Map.merge(company(), %{
        "account_id" => "a",
        "bankruptcy_ms" => nil,
        "unpaid" => 100,
        "unpaid_since" => 0,
        "arrears_since" => 0
      })

    bill = %{"id" => "bill", "company_id" => "c", "due_ms" => 0, "remaining" => 100}

    state =
      %{
        clock_ms: 1,
        entities: %{"companies" => %{"c" => row}, "operating_bills" => %{"bill" => bill}}
      }
      |> TijaraTides.Domain.EntityIndex.rebuild()

    # Simulate an incomplete loader: its index omits a persisted child.
    partial = %{
      state
      | entity_index: Map.delete(state.entity_index, {"operating_bills", "company_id", "c"})
    }

    {unchanged_children, effects} = Finance.settle_owned(partial, "c")
    assert unchanged_children.entities["operating_bills"]["bill"] == bill
    refute {"operating_bills", "bill", :delete, nil} in effects.children

    {paid, effects} = Finance.settle_owned(state, "c")
    refute Map.has_key?(paid.entities["operating_bills"], "bill")
    assert {"operating_bills", "bill", :delete, nil} in effects.children
    assert paid.entities["companies"]["c"]["cash"] == 900
  end

  test "loan and installment children stay typed through borrowing and accrual" do
    alias TijaraTides.Domain.CompanyFinance.{Loan, Installment}
    root = Finance.from_row(Map.merge(company(), %{"account_id" => "a", "bankruptcy_ms" => nil}))

    assert {:ok, borrowed, _, _} =
             Finance.loan_transition(
               root,
               "a",
               {:borrow, 10_000, "loan", %{suspended: false, available: 10_000, rate_bps: 800}},
               0
             )

    assert [%Loan{remaining: 10_000, rate_bps: 800} = loan] = borrowed.loans
    row = Loan.to_row(loan)
    assert Loan.from_row(row) == loan
    assert_raise KeyError, fn -> Loan.from_row(Map.delete(row, "interest_remainder")) end
    assert_raise ArgumentError, fn -> Loan.from_row(Map.put(row, "future_column", 1)) end
    {settled, _} = Finance.settle_finances(%{borrowed | cash: 0}, Finance.terms().period_ms)
    assert [%Installment{loan_id: "loan", principal_due: 2500} = bill] = settled.installments
    assert Installment.from_row(Installment.to_row(bill)) == bill
    assert_raise ArgumentError, fn -> Finance.from_row(Map.put(company(), "future_column", 1)) end
    assert Finance.from_row(Finance.to_row(root)) == root
  end
end
