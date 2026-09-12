defmodule TijaraTides.Domain.GuaranteesTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.Services.{Credit, CompanyFormation}
  alias TijaraTides.Domain.{Account, CompanyFinance, Game, Guarantees, Journal}

  setup do
    catalogue = TijaraTides.Infrastructure.GameCatalogue.all()
    state = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, catalogue)
    {:ok, state, _} = Account.seed_invite(state, "invite")
    {:ok, state, _} = Account.redeem(state, "invite", "session", %{id: "sponsor", wall_ms: 0})

    {:ok, state, _} =
      TijaraTides.CompanyFixture.create_company(
        state,
        Game.get(state, "accounts", "sponsor"),
        "Sponsor",
        "Jakarta",
        "general",
        %{id: "sponsor-company", catalogue: catalogue}
      )

    sponsor = Game.get(state, "accounts", "sponsor")

    beneficiary = %{
      sponsor
      | "id" => "beneficiary",
        "company_id" => nil,
        "inviter" => "sponsor",
        "suspended_ms" => 0,
        "bankruptcies" => 5
    }

    state = put_in(state, [:entities, "accounts", "beneficiary"], beneficiary)

    events =
      Map.new(1..5, fn i ->
        {"past-#{i}", %{"account_id" => "beneficiary", "created_ms" => 0, "restart_ms" => 0}}
      end)

    state = put_in(state, [:entities, "bankruptcy_events"], events)

    %{
      state: Journal.clear(state),
      sponsor: sponsor,
      beneficiary: beneficiary,
      catalogue: catalogue
    }
  end

  test "rate progression ages out but suspension persists", c do
    for {count, rate} <-
          Enum.with_index([800, 900, 1000, 1200, 1400, 1600, 1600])
          |> Enum.map(fn {r, n} -> {n, r} end) do
      events =
        Map.new(1..max(1, count), fn i ->
          {i, %{"account_id" => "beneficiary", "created_ms" => 0}}
        end)

      state =
        put_in(c.state, [:entities, "bankruptcy_events"], if(count == 0, do: %{}, else: events))

      assert CompanyFinance.rate(state, c.beneficiary) == rate
    end

    aged = %{c.state | clock_ms: CompanyFinance.terms().history_ms}
    assert CompanyFinance.rate(aged, c.beneficiary) == 800
    assert Guarantees.suspended?(Game.get(aged, "accounts", "beneficiary"))

    assert {:error, :account_suspended} =
             CompanyFormation.create_company(
               aged,
               c.beneficiary,
               "Blocked",
               %{id: "blocked"}
             )

    assert {:error, :account_suspended} =
             Game.execute(c.state, c.beneficiary, %{"action" => "invite"}, %{}, c.catalogue)
  end

  test "sponsor must cover own debt including interest with unreserved cash", c do
    assert Guarantees.sponsor_eligible?(c.state, c.sponsor)

    {:ok, state, _} =
      Credit.borrow(c.state, c.sponsor, 10_000_000, "sponsor-loan")

    locked = put_in(state, [:entities, "companies", "sponsor-company", "reserved"], 8_000_001)
    refute Guarantees.sponsor_eligible?(locked, c.sponsor)

    assert {:error, :guarantee_sponsor_unavailable} =
             Guarantees.pledge(locked, c.sponsor, "beneficiary", 5_000_000, "g")

    equal = put_in(state, [:entities, "companies", "sponsor-company", "reserved"], 8_000_000)
    assert Guarantees.sponsor_eligible?(equal, c.sponsor)
    accrued = put_in(equal, [:entities, "loans", "sponsor-loan", "interest_accrued"], 1)
    refute Guarantees.sponsor_eligible?(accrued, c.sponsor)
  end

  test "pledge reinstates, caps borrowing, fixes loan rate, and releases when the sponsor settles",
       c do
    assert {:error, :guarantee_amount} =
             Guarantees.pledge(c.state, c.sponsor, "beneficiary", 4_999_999, "g")

    assert {:error, :guarantee_amount} =
             Guarantees.pledge(c.state, c.sponsor, "beneficiary", 10_000_001, "g")

    assert {:error, :guarantee_not_sponsor} =
             Guarantees.pledge(c.state, c.sponsor, "sponsor", 5_000_000, "g")

    {:ok, state, _} = Guarantees.pledge(c.state, c.sponsor, "beneficiary", 5_000_000, "g")
    beneficiary = Game.get(state, "accounts", "beneficiary")
    refute Guarantees.suspended?(beneficiary)
    assert Game.get(state, "companies", "sponsor-company")["cash"] == 3_000_000

    assert {:error, :guarantee_exists} =
             Guarantees.pledge(state, c.sponsor, "beneficiary", 5_000_000, "g2")

    {:ok, state, _} =
      CompanyFormation.create_company(
        state,
        beneficiary,
        "Restart",
        %{id: "restart"}
      )

    beneficiary = Game.get(state, "accounts", "beneficiary")

    assert {:error, :loan_limit} =
             Credit.borrow(state, beneficiary, 5_000_001, "loan")

    {:ok, state, _} =
      Credit.borrow(state, beneficiary, 5_000_000, "loan")

    assert Game.get(state, "loans", "loan")["rate_bps"] == 1600

    {:ok, state, _} =
      Credit.recast(state, beneficiary, "loan", 1_000_000)

    assert Game.get(state, "loans", "loan")["rate_bps"] == 1600
    assert Guarantees.active(state, "beneficiary") != nil
    {:ok, state, _} = Credit.repay(state, beneficiary, "loan")

    # The escrow is the sponsor's to release, so repaying does not write its books.
    assert Guarantees.active(state, "beneficiary") != nil
    assert Game.get(state, "companies", "sponsor-company")["cash"] == 3_000_000
    assert [%{"settlement" => "release"}] = Guarantees.view(state, c.sponsor)["pledges"]

    state = TijaraTides.Domain.Services.FinancialSettlement.settle(state, ["sponsor-company"])
    assert Guarantees.active(state, "beneficiary") == nil
    assert Game.get(state, "companies", "sponsor-company")["cash"] == 8_000_000
    assert CompanyFinance.summary(state, beneficiary)["available"] == 0
  end

  test "settlement caps sponsor losses and refunds excess even to a bankrupt sponsor", c do
    {:ok, state, _} = Guarantees.pledge(c.state, c.sponsor, "beneficiary", 5_000_000, "g")
    state = put_in(state, [:entities, "companies", "sponsor-company", "bankruptcy_ms"], 0)

    forfeit = fn debt ->
      state
      |> put_in([:entities, "bankruptcy_events", "failed"], %{
        "id" => "failed",
        "company_id" => "failed",
        "account_id" => "beneficiary",
        "created_ms" => 0,
        "restart_ms" => 0,
        "reason" => "forced",
        "guarantee_id" => "g",
        "guaranteed_debt" => debt
      })
      |> TijaraTides.Domain.Services.FinancialSettlement.settle(["sponsor-company"])
    end

    settled = forfeit.(2_000_000)
    assert Game.get(settled, "guarantees", "g")["forfeited"] == 2_000_000
    assert Game.get(settled, "companies", "sponsor-company")["cash"] == 6_000_000
    assert Game.get(settled, "companies", "sponsor-company")["profit"] == -2_000_000

    # Settling again is a no-op: the guarantee is no longer pledged.
    assert TijaraTides.Domain.Services.FinancialSettlement.settle(settled, ["sponsor-company"]) ==
             settled

    assert Game.get(forfeit.(9_000_000), "guarantees", "g")["forfeited"] == 5_000_000
  end

  test "a refundable pledge pays sponsor arrears before foreclosure", c do
    state = guaranteed_loan(c)
    borrower = Game.get(state, "accounts", "beneficiary")
    {:ok, state, _} = Credit.repay(state, borrower, "loan")
    company = Game.get(state, "companies", "sponsor-company")

    state =
      TijaraTides.Domain.State.put(state, "companies", "sponsor-company", %{
        company
        | "cash" => 0,
          "unpaid" => 1_000_000,
          "unpaid_since" => 0,
          "arrears_since" => 0
      })

    state = %{state | clock_ms: CompanyFinance.terms().grace_ms + 1}
    settled = TijaraTides.Domain.Services.FinancialSettlement.settle(state, ["sponsor-company"])
    company = Game.get(settled, "companies", "sponsor-company")
    assert company["bankruptcy_ms"] == nil
    assert company["unpaid"] == 0
    assert company["cash"] == 4_000_000
    assert Game.get(settled, "accounts", "sponsor")["company_id"] == "sponsor-company"
  end

  test "drawing records the guarantee on the loan without writing sponsor children", c do
    {:ok, state, _} = Guarantees.pledge(c.state, c.sponsor, "beneficiary", 5_000_000, "g")

    {:ok, state, _} =
      CompanyFormation.create_company(
        state,
        Game.get(state, "accounts", "beneficiary"),
        "Restart",
        %{id: "restart"}
      )

    before = state

    {:ok, state, _} =
      Credit.borrow(state, Game.get(state, "accounts", "beneficiary"), 5_000_000, "loan")

    assert Game.get(state, "loans", "loan")["guarantee_id"] == "g"
    assert Game.get(state, "guarantees", "g") == Game.get(before, "guarantees", "g")

    assert Game.get(state, "companies", "sponsor-company") ==
             Game.get(before, "companies", "sponsor-company")

    refute Enum.any?(TijaraTides.Domain.ChangeSet.since(before, state), fn {{kind, _}, _} ->
             kind == "guarantees"
           end)
  end

  # Two-legged forfeit: a beneficiary's bankruptcy must not write the sponsor's books.
  defp guaranteed_loan(c) do
    {:ok, state, _} = Guarantees.pledge(c.state, c.sponsor, "beneficiary", 5_000_000, "g")

    {:ok, state, _} =
      CompanyFormation.create_company(
        state,
        Game.get(state, "accounts", "beneficiary"),
        "Restart",
        %{id: "restart"}
      )

    {:ok, state, _} =
      Credit.borrow(state, Game.get(state, "accounts", "beneficiary"), 5_000_000, "loan")

    state
  end

  test "beneficiary bankruptcy records the debt without touching the sponsor's books", c do
    state = guaranteed_loan(c)
    sponsor_company = Game.get(state, "companies", "sponsor-company")

    {:ok, state, _} =
      TijaraTides.Domain.Services.Bankruptcy.bankrupt(
        state,
        Game.get(state, "accounts", "beneficiary"),
        "forced"
      )

    assert Game.get(state, "companies", "sponsor-company") == sponsor_company
    assert Game.get(state, "guarantees", "g")["status"] == "pledged"
    assert Game.get(state, "bankruptcy_events", "restart")["guaranteed_debt"] == 5_000_000
  end

  test "the sponsor's own settlement forfeits the escrow recorded by the bankruptcy", c do
    state = guaranteed_loan(c)

    {:ok, state, _} =
      TijaraTides.Domain.Services.Bankruptcy.bankrupt(
        state,
        Game.get(state, "accounts", "beneficiary"),
        "forced"
      )

    # The expense must land when the sponsor settles, not when the beneficiary fails.
    assert Game.get(state, "companies", "sponsor-company")["profit"] == 0

    settled = TijaraTides.Domain.Services.FinancialSettlement.settle(state, ["sponsor-company"])

    assert Game.get(settled, "guarantees", "g")["status"] == "claimed"
    assert Game.get(settled, "guarantees", "g")["forfeited"] == 5_000_000
    assert Game.get(settled, "companies", "sponsor-company")["profit"] == -5_000_000
  end

  test "a forfeit awaiting the sponsor's settlement is reported as pending", c do
    state = guaranteed_loan(c)

    {:ok, state, _} =
      TijaraTides.Domain.Services.Bankruptcy.bankrupt(
        state,
        Game.get(state, "accounts", "beneficiary"),
        "forced"
      )

    [pledge] = Guarantees.view(state, c.sponsor)["pledges"]
    assert pledge["settlement"] == "claim"
    assert pledge["settlement_amount"] == 5_000_000
  end
end
