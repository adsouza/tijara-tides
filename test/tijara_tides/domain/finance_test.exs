defmodule TijaraTides.Domain.FinanceTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.Services.{Credit, FinancialSettlement, Bankruptcy, CompanyFormation}
  alias TijaraTides.Domain.{Account, CompanyFinance, Fleet, Game, Journal}

  setup do
    catalogue = TijaraTides.Infrastructure.GameCatalogue.all()
    state = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, catalogue)
    {:ok, state, _} = Account.seed_invite(state, "invite")
    {:ok, state, _} = Account.redeem(state, "invite", "session", %{id: "account", wall_ms: 0})

    {:ok, state, _} =
      TijaraTides.CompanyFixture.create_company(
        state,
        Game.get(state, "accounts", "account"),
        "Loan test",
        "Jakarta",
        "general",
        %{id: "company", catalogue: catalogue}
      )

    %{
      state: Journal.clear(state),
      account: Game.get(state, "accounts", "account"),
      catalogue: catalogue
    }
  end

  defp loan(c, amount \\ 100_000),
    do: Credit.borrow(c.state, c.account, amount, "loan")

  defp tick(state, ms),
    do: FinancialSettlement.settle(%{state | clock_ms: ms})

  test "company-scoped settlement leaves unrelated loans untouched", c do
    {:ok, state, _} = loan(c)

    other =
      state.entities["loans"]["loan"]
      |> Map.put("id", "other")
      |> Map.put("company_id", "unrelated")

    state = TijaraTides.Domain.State.put(state, "loans", "other", other)
    state = TijaraTides.Domain.EntityIndex.rebuild(%{state | clock_ms: 1000})
    settled = FinancialSettlement.settle(state, ["company"])
    assert settled.entities["loans"]["other"] == other
    assert settled.entities["loans"]["loan"]["interest_accrued"] > 0
  end

  test "borrowing is a liability, not profit, with conservative available credit", c do
    before = CompanyFinance.summary(c.state, c.account)
    {:ok, state, _} = loan(c)

    assert state.entities["companies"]["company"]["cash"] ==
             c.state.entities["companies"]["company"]["cash"] + 100_000

    assert state.entities["companies"]["company"]["profit"] == 0
    assert CompanyFinance.summary(state, c.account)["available"] == before["available"] - 100_000

    assert [%{entries: [{"cash_available", 100_000}, {"loan_principal", -100_000}]}] =
             state.journal

    assert length(hd(CompanyFinance.summary(state, c.account)["loans"])["schedule"]) == 4
  end

  test "invalid loans and excessive credit cannot move money", c do
    for amount <- [0, -1, nil, "100", 99],
        do:
          assert(
            {:error, :loan_invalid_amount} ==
              Credit.borrow(c.state, c.account, amount, "x")
          )

    assert {:error, :loan_limit} =
             Credit.borrow(
               c.state,
               c.account,
               CompanyFinance.summary(c.state, c.account)["available"] + 1,
               "x"
             )

    assert {:error, :finance_no_company} =
             Credit.borrow(c.state, %{"company_id" => nil}, 100, "x")

    state =
      Enum.reduce(1..8, c.state, fn n, s ->
        {:ok, s, _} = Credit.borrow(s, c.account, 100, to_string(n))
        s
      end)

    assert {:error, :loan_count_limit} =
             Credit.borrow(state, c.account, 100, "ninth")
  end

  test "installments accrue and settle once with declining interest", c do
    {:ok, state, _} = loan(c)
    period = CompanyFinance.terms().period_ms
    state = tick(state, period)
    l = state.entities["loans"]["loan"]
    assert l["remaining"] == 75_000
    assert l["interest_due"] == 0
    assert state.entities["companies"]["company"]["profit"] == -8000
    assert FinancialSettlement.settle(state) == state
    state = Enum.reduce(2..4, state, fn n, s -> tick(s, n * period) end)
    assert state.entities["loans"]["loan"]["status"] == "repaid"
    assert state.entities["companies"]["company"]["profit"] == -20_000
    assert CompanyFinance.summary(state, c.account)["debt"] == 0
  end

  test "recast pays accrued interest and reduces installments without extending maturity", c do
    {:ok, state, _} = loan(c)
    state = tick(state, div(CompanyFinance.terms().period_ms, 2))
    before = state.entities["loans"]["loan"]
    cash = state.entities["companies"]["company"]["cash"]

    {:ok, state, result} =
      Credit.recast(Journal.clear(state), c.account, "loan", 54_000)

    assert result == %{"paid" => 54_000, "principal_reduction" => 50_000, "installment" => 12_500}
    after_loan = state.entities["loans"]["loan"]
    assert after_loan["remaining"] == 50_000
    assert after_loan["interest_accrued"] == 0
    assert after_loan["next_due_ms"] == before["next_due_ms"]
    assert after_loan["periods_left"] == before["periods_left"]
    assert state.entities["companies"]["company"]["cash"] == cash - 54_000

    assert [
             %{
               entries: [
                 {"loan_principal", 50_000},
                 {"loan_interest", 4_000},
                 {"cash_available", -54_000}
               ]
             }
           ] = state.journal

    assert hd(CompanyFinance.summary(state, c.account)["loans"])["schedule"]
           |> hd()
           |> Map.fetch!("interest") == 2_000

    final = tick(state, 4 * CompanyFinance.terms().period_ms)
    assert final.entities["loans"]["loan"]["status"] == "repaid"
    assert final.entities["loans"]["loan"]["remaining"] == 0
  end

  test "recasts reject invalid amounts, protected cash, other owners and overdue loans", c do
    {:ok, state, _} = loan(c)

    assert {:error, :loan_not_owned} =
             Credit.recast(
               state,
               %{c.account | "id" => "other"},
               "loan",
               50_000
             )

    for amount <- [nil, "50000", 0, 99, 100_001] do
      assert {:error, :loan_recast_amount} =
               Credit.recast(state, c.account, "loan", amount)
    end

    assert {:ok, closed, _} =
             Credit.recast(state, c.account, "loan", 100_000)

    assert closed.entities["loans"]["loan"]["status"] == "repaid"
    cash = state.entities["companies"]["company"]["cash"]
    locked = put_in(state, [:entities, "companies", "company", "reserved"], cash)

    assert {:error, :loan_repayment_funds} =
             Credit.recast(locked, c.account, "loan", 50_000)

    overdue = tick(locked, CompanyFinance.terms().period_ms)

    assert {:error, :loan_recast_unavailable} =
             Credit.recast(overdue, c.account, "loan", 50_000)
  end

  test "early repayment waives future interest and cannot farm credit increases", c do
    limit = CompanyFinance.summary(c.state, c.account)["limit"]
    {:ok, state, _} = loan(c)

    assert {:error, :loan_not_owned} =
             Credit.repay(state, %{"company_id" => "other"}, "loan")

    {:ok, state, %{"repaid" => 100_000}} =
      Credit.repay(state, c.account, "loan")

    assert state.entities["companies"]["company"]["profit"] == 0
    assert CompanyFinance.summary(state, c.account)["limit"] == limit

    assert {:ok, _, %{"repaid" => 0}} =
             Credit.repay(state, c.account, "loan")

    assert FinancialSettlement.settle(%{
             state
             | clock_ms: 10 * CompanyFinance.terms().period_ms
           }).entities["loans"][
             "loan"
           ]["interest_due"] == 0
  end

  test "continuous interest is independent of tick size, not overdue before its due date, and paid on early closure",
       c do
    {:ok, initial, _} = loan(c)
    period = CompanyFinance.terms().period_ms
    halfway = tick(initial, div(period, 2))
    split = Enum.reduce(1..100, initial, fn n, state -> tick(state, div(period * n, 200)) end)
    assert split.entities == halfway.entities
    loan = halfway.entities["loans"]["loan"]
    assert loan["interest_accrued"] == 4000
    assert loan["interest_due"] == 0

    assert hd(hd(CompanyFinance.summary(halfway, c.account)["loans"])["schedule"])["interest"] ==
             8000

    assert CompanyFinance.summary(halfway, c.account)["arrears"] == 0
    assert CompanyFinance.summary(halfway, c.account)["deadline"] == nil
    assert FinancialSettlement.settle(halfway) == halfway

    assert {:ok, repaid, %{"repaid" => 104_000}} =
             Credit.repay(halfway, c.account, "loan")

    assert repaid.entities["companies"]["company"]["profit"] == -4000
    assert repaid.entities["loans"]["loan"]["interest_accrued"] == 0
    assert tick(repaid, period).entities == repaid.entities

    tiny = tick(initial, 1)
    assert tiny.entities["loans"]["loan"]["interest_accrued"] == 1
    assert tick(tiny, 2).entities["loans"]["loan"]["interest_accrued"] == 1
  end

  test "protected funds cannot service debt; partial payments retain the original grace deadline",
       c do
    {:ok, state, _} = loan(c)
    cash = state.entities["companies"]["company"]["cash"]
    state = put_in(state, [:entities, "companies", "company", "reserved"], cash)

    assert {:error, :loan_repayment_funds} =
             Credit.repay(state, c.account, "loan")

    period = CompanyFinance.terms().period_ms
    waiting = tick(state, period)
    assert waiting.entities["companies"]["company"]["cash"] == cash
    assert CompanyFinance.summary(waiting, c.account)["available"] == 0
    assert FinancialSettlement.settle(waiting) == waiting
    deadline = CompanyFinance.summary(waiting, c.account)["deadline"]

    partial =
      put_in(waiting, [:entities, "companies", "company", "reserved"], cash - 500)
      |> FinancialSettlement.settle()

    assert partial.entities["loans"]["loan"]["interest_due"] == 7500
    assert CompanyFinance.summary(partial, c.account)["deadline"] == deadline

    recovered =
      put_in(partial, [:entities, "companies", "company", "reserved"], 0)
      |> FinancialSettlement.settle()

    assert CompanyFinance.summary(recovered, c.account)["deadline"] == nil
  end

  test "operating bills and installments compete oldest due first", c do
    {:ok, state, _} = loan(c)
    period = CompanyFinance.terms().period_ms

    state =
      state
      |> put_in([:entities, "companies", "company", "unpaid"], 2000)
      |> put_in([:entities, "companies", "company", "cash"], 1500)
      |> CompanyFinance.operating_bill("company", 1000, period - 1)
      |> CompanyFinance.operating_bill("company", 1000, period + 1)

    state = tick(state, period + 1)
    assert state.entities["companies"]["company"]["unpaid"] == 1000
    assert state.entities["loans"]["loan"]["interest_due"] == 7500
    assert map_size(state.entities["operating_bills"]) == 1
  end

  test "forced bankruptcy uses only active time and never transfers old assets", c do
    {:ok, state, _} = loan(c)
    state = put_in(state, [:entities, "companies", "company", "cash"], 0)
    due = CompanyFinance.terms().period_ms
    waiting = tick(state, due)
    assert FinancialSettlement.settle(waiting) == waiting
    state = tick(waiting, due + CompanyFinance.terms().grace_ms)
    account = state.entities["accounts"]["account"]
    assert account["company_id"] == nil
    assert account["bankruptcies"] == 1
    assert state.entities["companies"]["company"]["bankruptcy_ms"] == state.clock_ms
    assert state.entities["loans"]["loan"]["status"] == "defaulted"
    assert map_size(state.entities["ships"]) == 3

    assert {:error, :bankruptcy_cooldown} =
             CompanyFormation.create_company(state, account, "New", %{
               id: "new",
               catalogue: c.catalogue
             })

    assert {:error, :finance_no_company} =
             Bankruptcy.bankrupt(state, c.account)

    state = %{state | clock_ms: state.clock_ms + CompanyFinance.terms().cooldown_ms}

    {:ok, new, _} =
      CompanyFormation.create_company(state, account, "New", %{
        id: "new",
        catalogue: c.catalogue
      })

    assert new.entities["companies"]["new"]["cash"] < 20_000_000

    assert Enum.all?(Game.private(new, new.entities["accounts"]["account"])["ships"], fn {_, s} ->
             s["company_id"] == "new"
           end)

    assert Game.public(new, c.catalogue)["companies"]["company"]["bankruptcy_ms"] != nil
    assert new.entities["accounts"]["account"]["bankruptcies"] == 1
  end

  test "voluntary bankruptcy cancels orders but committed sailing finishes", c do
    ship = c.state.entities["ships"]["company:1"]
    quote = Fleet.voyage_quote(ship, "Singapore", c.catalogue)

    {:ok, state, _} =
      Fleet.sail(c.state, c.account, ship["id"], "Singapore", quote["fuel"], c.catalogue)

    {:ok, state, _} =
      TijaraTides.Domain.ShipInstructions.change_onward(
        state,
        c.account,
        ship["id"],
        "Singapore",
        "Jakarta",
        c.catalogue,
        true
      )

    state =
      put_in(
        state,
        [:entities, "companies", "company", "unpaid"],
        state.entities["companies"]["company"]["cash"] + 1
      )

    {:ok, state, _} = Bankruptcy.bankrupt(state, c.account)
    assert state.entities["visit_plans"] == %{}
    arrived = Fleet.advance(%{state | clock_ms: quote["duration_ms"]}, quote["duration_ms"])
    assert arrived.entities["ships"][ship["id"]]["status"] == "docked"
    assert arrived.entities["companies"]["company"]["reserved"] == 0
    assert arrived.entities["companies"]["company"]["unpaid"] == 0
  end

  test "voluntary bankruptcy requires liabilities to exceed unreserved cash", c do
    assert {:error, :bankruptcy_cash_covers_debts} =
             Bankruptcy.bankrupt(c.state, c.account)

    {:ok, state, _} = loan(c)
    state = put_in(state, [:entities, "companies", "company", "cash"], 100_000)
    refute CompanyFinance.can_declare_bankruptcy?(state, c.account)

    assert {:error, :bankruptcy_cash_covers_debts} =
             Bankruptcy.bankrupt(state, c.account)

    reserved = put_in(state, [:entities, "companies", "company", "reserved"], 1)
    assert CompanyFinance.can_declare_bankruptcy?(reserved, c.account)
    assert {:ok, _, _} = Bankruptcy.bankrupt(reserved, c.account)
    accrued = tick(state, div(CompanyFinance.terms().period_ms, 2))
    assert CompanyFinance.can_declare_bankruptcy?(accrued, c.account)
  end

  test "counted bankruptcies age out and credit limits recover", c do
    troubled =
      put_in(
        c.state,
        [:entities, "companies", "company", "unpaid"],
        c.state.entities["companies"]["company"]["cash"] + 1
      )

    {:ok, state, _} = Bankruptcy.bankrupt(troubled, c.account)
    a = state.entities["accounts"]["account"]
    assert CompanyFinance.counted(state, a) == 1
    assert CompanyFinance.summary(state, a)["limit"] == 12_500_000
    restored = %{state | clock_ms: state.clock_ms + CompanyFinance.terms().history_ms}
    assert CompanyFinance.counted(restored, a) == 0
    assert CompanyFinance.summary(restored, a)["limit"] == 25_000_000
    assert a["bankruptcies"] == 1
  end
end
