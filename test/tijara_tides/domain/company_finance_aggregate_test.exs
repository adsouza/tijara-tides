defmodule TijaraTides.Domain.CompanyFinanceAggregateTest do
  alias TijaraTides.Domain.CompanyFinanceWorld, as: FinanceWorld
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.Services.{FinancialSettlement}
  alias TijaraTides.Domain.CompanyFinance, as: Finance

  defp company do
    %{"id" => "c", "cash" => 1000, "reserved" => 0, "unpaid" => 0, "profit" => 0}
  end

  test "reserving cash prevents a later purchase from spending it" do
    finance = Finance.Rows.decode(company())
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
    state = FinanceWorld.post(state, "c", "loan_draw", entries)
    assert state.entities["companies"]["c"]["cash"] == 1500
    assert state.entities["companies"]["c"]["profit"] == 0
    assert hd(state.journal).entries == entries

    assert_raise ArgumentError, fn ->
      FinanceWorld.post(state, "c", "bad", [{"cash_available", 1}])
    end

    assert_raise ArgumentError, fn ->
      Finance.apply_entries(Finance.Rows.decode(company()), [
        {"payables", 1},
        {"cash_available", -1}
      ])
    end
  end

  test "crew creates arrears while reserved fuel remains available only for fuel" do
    row = %{company() | "reserved" => 900}
    state = %{clock_ms: 20, entities: %{"companies" => %{"c" => row}}}

    state =
      FinanceWorld.ship_operations(state, "c", "ship", %{
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

    assert FinanceWorld.fetch(state, "c").bills |> hd() |> Map.fetch!(:remaining) == 100
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
      Finance.Rows.decode(row)
      | bills: [
          Finance.OperatingBill.from_row(%{
            "id" => "b",
            "company_id" => "c",
            "due_ms" => 0,
            "remaining" => 100
          })
        ]
    }

    {next, effects} = Finance.settle_finances(root, Finance.terms().grace_ms)
    assert effects.receivership
    assert next.unpaid == 100
    assert next.bankruptcy_ms == nil
    assert Enum.map(next.bills, & &1.id) == ["b"]
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

      assert {_, %{receivership: true}} = FinanceWorld.settle_owned(state, "c")
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

    {unchanged_children, effects} = FinanceWorld.settle_owned(partial, "c")
    assert unchanged_children.entities["operating_bills"]["bill"] == bill
    refute {"operating_bills", "bill", :delete, nil} in effects.children

    {paid, effects} = FinanceWorld.settle_owned(state, "c")
    refute Map.has_key?(paid.entities["operating_bills"], "bill")
    assert {"operating_bills", "bill", :delete, nil} in effects.children
    assert paid.entities["companies"]["c"]["cash"] == 900
  end

  test "loan and installment children stay typed through borrowing and accrual" do
    alias TijaraTides.Domain.CompanyFinance.{Loan, Installment}

    root =
      Finance.Rows.decode(Map.merge(company(), %{"account_id" => "a", "bankruptcy_ms" => nil}))

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

    assert_raise ArgumentError, fn ->
      Finance.Rows.decode(Map.put(company(), "future_column", 1))
    end

    assert Finance.Rows.decode(Finance.Rows.encode(root)) == root
  end

  test "receivership emits closed loan history and explicit bill deletions with balanced write-offs" do
    root = %{Finance.Rows.decode(company()) | account_id: "a"}

    {:ok, borrowed, _, _} =
      Finance.loan_transition(
        root,
        "a",
        {:borrow, 10_000, "loan", %{suspended: false, available: 10_000, rate_bps: 800}},
        0
      )

    {overdue, _} = Finance.settle_finances(%{borrowed | cash: 0}, Finance.terms().period_ms)

    overdue = %{
      overdue
      | unpaid: 100,
        unpaid_since: 0,
        bills: [%Finance.OperatingBill{id: "bill", company_id: "c", due_ms: 0, remaining: 100}]
    }

    {closed, effects} = Finance.close_in_receivership(overdue, Finance.terms().period_ms + 1)
    assert closed.loans == []
    assert closed.bills == []
    assert closed.installments == []
    assert closed.unpaid == 0
    assert closed.arrears_since == nil
    assert closed.unpaid_since == nil
    assert closed.bankruptcy_ms == Finance.terms().period_ms + 1
    assert {:bills, "bill", :delete, nil} in effects.children
    assert Enum.any?(effects.children, &match?({:installments, _, :delete, nil}, &1))
    assert {:loans, "loan", :put, loan} = Enum.find(effects.children, &(elem(&1, 0) == :loans))
    assert loan.status == "defaulted"
    assert loan.remaining == 0
    assert loan.interest_due == 0
    assert Enum.any?(effects.journal, &({"loan_principal", 10_000} in &1.entries))
    assert Enum.any?(effects.journal, &({"payables", 100} in &1.entries))

    assert Enum.all?(
             effects.journal,
             &(Enum.sum(Enum.map(&1.entries, fn {_, amount} -> amount end)) == 0)
           )
  end
end
