defmodule TijaraTides.Domain.DormancyTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{AccountWorld, CompanyFinanceWorld, Game, State, Visibility}
  alias TijaraTides.Domain.Account.Dormancy
  alias TijaraTides.Domain.AccountWorld.EmailIdentity
  alias TijaraTides.Domain.Services.Estates

  defp fixture do
    catalogue =
      TijaraTides.Infrastructure.GameCatalogue.all()
      |> Map.put("dormancy", %{"absence_ms" => 100, "warning_ms" => 200})

    state = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, catalogue)
    {:ok, state, _} = Game.seed_invite(state, "invite")
    {:ok, state, _} = Game.redeem(state, "invite", "session", %{id: "owner", wall_ms: 0})

    {:ok, state, _} =
      Game.execute(
        state,
        State.get(state, "accounts", "owner"),
        %{"action" => "company", "name" => "Absentee Shipping"},
        %{id: "company", catalogue: catalogue},
        catalogue
      )

    state = AccountWorld.advance_dormancy(state, 0, catalogue)
    {state, catalogue}
  end

  test "warning uses wall time, snapshots a full notice period and never counts economic automation" do
    {state, catalogue} = fixture()

    state =
      State.put(state, "company_activity", "company", %{
        "company_id" => "company",
        "last_action_ms" => 100
      })

    assert AccountWorld.advance_dormancy(state, 99, catalogue) == state
    warned = AccountWorld.advance_dormancy(state, 100, catalogue)
    assert warned.clock_ms == 0
    assert State.get(warned, "company_dormancy", "company")["closes_ms"] == 300
    assert State.get(warned, "notices", "dormancy:company")["code"] == "company.dormancy_warning"
    assert State.entities(warned, "email_requests") == %{}
    revised = Map.put(catalogue, "dormancy", %{"absence_ms" => 1, "warning_ms" => 1})
    assert AccountWorld.advance_dormancy(warned, 299, revised) == warned
    closed = AccountWorld.advance_dormancy(warned, 300, revised)
    assert State.get(closed, "accounts", "owner")["company_id"] == nil
    assert State.get(closed, "accounts", "owner")["bankruptcies"] == 0
    assert AccountWorld.counted(closed, State.get(closed, "accounts", "owner")) == 0
    assert State.entities(closed, "bankruptcy_events") == %{}
    assert State.get(closed, "company_activity", "company") == nil
    assert State.get(closed, "company_dormancy", "company")["closed_ms"] == 300

    assert Visibility.public(closed, catalogue)["companies"]["company"]["closure_reason"] ==
             "dormant"

    assert AccountWorld.advance_dormancy(closed, 9999, catalogue) == closed
    assert TijaraTides.Domain.ChangeSet.assert_complete!(state, closed) == :ok
  end

  test "an authenticated return cancels notice and queued email, including stale delivery acknowledgements" do
    {state, catalogue} = fixture()
    state = AccountWorld.verify_email(state, "owner", "owner@example.com", "session", 9999)
    warned = AccountWorld.advance_dormancy(state, 100, catalogue)
    email = State.get(warned, "email_requests", "dormancy:company:100")
    assert email["delivery"] == "pending"

    assert {:error, :email_link_invalid} =
             EmailIdentity.redeem(warned, email["token_hash"], "other", nil, %{wall_ms: 101})

    returned = AccountWorld.owner_visit(warned, State.get(warned, "accounts", "owner"), 299)
    assert State.get(returned, "company_dormancy", "company")["last_visit_ms"] == 299
    assert State.get(returned, "company_dormancy", "company")["closes_ms"] == nil
    assert State.get(returned, "notices", "dormancy:company") == nil

    refute Enum.any?(
             Visibility.private(returned, State.get(returned, "accounts", "owner"))["notices"],
             &(&1["code"] == "company.dormancy_warning")
           )

    assert State.get(returned, "email_requests", email["id"])["delivery"] == "ignored"
    assert EmailIdentity.delivered(returned, email) == returned
    assert EmailIdentity.delivery_failed(returned, email, 300) == returned
    next = AccountWorld.advance_dormancy(returned, 399, catalogue)
    assert State.get(next, "email_requests", "dormancy:company:399")["delivery"] == "pending"
    assert State.get(next, "company_dormancy", "company")["closes_ms"] == 599
  end

  test "legacy worlds start a fresh baseline; resumed warnings close without advancing the world clock" do
    {state, catalogue} = fixture()
    legacy = State.delete(state, "company_dormancy", "company")
    restored = AccountWorld.advance_dormancy(legacy, 1_000_000, catalogue)
    assert State.get(restored, "company_dormancy", "company")["last_visit_ms"] == 1_000_000
    assert State.get(restored, "company_dormancy", "company")["warned_ms"] == nil
    warned = AccountWorld.advance_dormancy(restored, 1_000_100, catalogue)
    closed = AccountWorld.advance_dormancy(warned, 2_000_000, catalogue)
    assert closed.clock_ms == 0
    assert State.get(closed, "company_dormancy", "company")["closed_ms"] == 2_000_000
    assert State.get(closed, "companies", "company")["bankruptcy_ms"] == 0

    assert AccountWorld.owner_visit(closed, State.get(closed, "accounts", "owner"), 2_000_001) ==
             closed
  end

  test "ordinary bankruptcy during absence cancels obsolete warnings and still counts normally" do
    {state, catalogue} = fixture()
    state = AccountWorld.verify_email(state, "owner", "owner@example.com", "session", 9999)
    warned = AccountWorld.advance_dormancy(state, 100, catalogue)

    {:ok, bankrupt, _} =
      TijaraTides.Domain.Services.Bankruptcy.bankrupt(
        warned,
        State.get(warned, "accounts", "owner"),
        "forced"
      )

    assert State.get(bankrupt, "accounts", "owner")["bankruptcies"] == 1
    assert State.get(bankrupt, "company_dormancy", "company")["closed_ms"] == nil
    assert State.get(bankrupt, "company_dormancy", "company")["closes_ms"] == nil
    assert State.get(bankrupt, "email_requests", "dormancy:company:100")["delivery"] == "ignored"
    assert State.get(bankrupt, "notices", "dormancy:company") == nil
    assert AccountWorld.advance_dormancy(bankrupt, 300, catalogue) == bankrupt

    assert Visibility.public(bankrupt, catalogue)["companies"]["company"]["closure_reason"] ==
             "bankruptcy"
  end

  test "dormant estate cash leaves circulation and a replacement does not restore its assets" do
    {state, catalogue} = fixture()

    state =
      CompanyFinanceWorld.post(state, "company", "test_capital", [
        {"cash_available", 10_000},
        {"capital", -10_000}
      ])

    state =
      AccountWorld.advance_dormancy(state, 100, catalogue)
      |> AccountWorld.advance_dormancy(300, catalogue)

    closed = Estates.advance(state, catalogue)
    assert State.get(closed, "companies", "company")["cash"] == 0
    assert Enum.count(closed.journal, &(&1.kind == "estate_closed")) == 1
    assert Estates.advance(closed, catalogue) == closed
    owner = State.get(closed, "accounts", "owner")
    assert AccountWorld.restart_at(closed, owner) == 0

    {:ok, fresh, _} =
      Game.execute(
        closed,
        owner,
        %{"action" => "company", "name" => "Replacement"},
        %{id: "replacement", catalogue: catalogue},
        catalogue
      )

    assert State.get(fresh, "companies", "replacement")["cash"] == 0
    assert State.get(fresh, "accounts", "owner")["bankruptcies"] == 0
  end

  test "durable settings reject nonpositive intervals and backward visits cannot reduce absence baseline" do
    assert Dormancy.settings(%{}) == %{
             "absence_ms" => 30 * 86_400_000,
             "warning_ms" => 7 * 86_400_000
           }

    for value <- [0, -1, "100", nil] do
      assert_raise ArgumentError, fn ->
        Dormancy.settings(%{"dormancy" => %{"warning_ms" => value}})
      end
    end

    record = Dormancy.new("c", "a", 123)
    assert Dormancy.visit(record, 12).last_visit_ms == 123
    assert Dormancy.from_row(Dormancy.to_row(record)) == record
  end

  test "closure cancels route templates while leaving owned hulls for estate auctions" do
    {state, catalogue} = fixture()
    account = State.get(state, "accounts", "owner")
    state = TijaraTides.CompanyFixture.fund(state, account, "Jakarta", "general", catalogue)

    {:ok, state, _} =
      TijaraTides.Domain.ShipRoutes.execute(
        state,
        account,
        %{"ship" => "company:1", "operation" => "add_stop", "port" => "Singapore"},
        %{id: "stop", catalogue: catalogue}
      )

    assert map_size(State.entities(state, "ship_routes")) == 1

    closed =
      AccountWorld.advance_dormancy(state, 100, catalogue)
      |> AccountWorld.advance_dormancy(300, catalogue)

    assert State.entities(closed, "ship_routes") == %{}
    assert State.entities(closed, "route_stops") == %{}
    assert State.get(closed, "ships", "company:1")["company_id"] == "company"
    offered = Estates.advance(closed, catalogue)

    assert Enum.any?(State.entities(offered, "auctions"), fn {_, a} ->
             a["ship_id"] == "company:1" and a["company_id"] == "company"
           end)
  end

  test "dormant closure records guaranteed debt separately and settles sponsor escrow once" do
    alias TijaraTides.Domain.CompanyFinanceWorld.Guarantees
    {state, catalogue} = fixture()
    {:ok, state, _} = Game.seed_invite(state, "sponsor-invite")

    {:ok, state, _} =
      Game.redeem(state, "sponsor-invite", "sponsor-session", %{id: "sponsor", wall_ms: 0})

    {:ok, state, _} =
      Game.execute(
        state,
        State.get(state, "accounts", "sponsor"),
        %{"action" => "company", "name" => "Sponsor"},
        %{id: "sponsor-company", catalogue: catalogue},
        catalogue
      )

    state =
      CompanyFinanceWorld.post(state, "sponsor-company", "test_capital", [
        {"cash_available", 6_000_000},
        {"capital", -6_000_000}
      ])

    pledge = %{
      "id" => "pledge",
      "company_id" => "sponsor-company",
      "sponsor_id" => "sponsor",
      "beneficiary_id" => "owner",
      "borrower_company_id" => "company",
      "amount" => 5_000_000,
      "forfeited" => 0,
      "status" => "pledged",
      "created_ms" => 0
    }

    state =
      State.put(state, "guarantees", "pledge", pledge)
      |> CompanyFinanceWorld.post("sponsor-company", "guarantee_pledge", [
        {"guarantee_escrow", 5_000_000},
        {"cash_available", -5_000_000}
      ])

    {:ok, state, _} =
      TijaraTides.Domain.Services.Credit.borrow(
        state,
        State.get(state, "accounts", "owner"),
        100_000,
        "loan"
      )

    closed =
      AccountWorld.advance_dormancy(state, 100, catalogue)
      |> AccountWorld.advance_dormancy(300, catalogue)

    record = State.get(closed, "company_dormancy", "company")
    assert record["guarantee_id"] == "pledge"
    assert record["guaranteed_debt"] == 100_000
    assert State.entities(closed, "bankruptcy_events") == %{}
    assert State.get(closed, "loans", "loan")["status"] == "defaulted"
    assert Guarantees.outcome(closed, pledge) == {"claim", 100_000}
    settled = Guarantees.settle(closed)
    assert State.get(settled, "guarantees", "pledge")["forfeited"] == 100_000
    assert State.get(settled, "companies", "sponsor-company")["cash"] == 5_900_000
    assert Guarantees.settle(settled) == settled
  end
end
