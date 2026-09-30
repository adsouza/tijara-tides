defmodule TijaraTides.Domain.InvitationAccrualTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{Account, AccountWorld, ChangeSet, EntityIndex, Journal, State}
  alias TijaraTides.Domain.Account.InvitationProgress
  alias TijaraTides.Domain.AccountWorld.InvitationAccrual
  @day 86_400_000

  defp world(quota \\ 0) do
    account = %{Account.new("a", "sponsor", false, 0) | company_id: "c", invite_quota: quota}

    %{clock_ms: 0, entities: %{}}
    |> State.put("accounts", "a", Account.Rows.encode(account))
    |> State.put("companies", "c", %{
      "id" => "c",
      "account_id" => "a",
      "unpaid" => 0,
      "arrears_since" => nil,
      "bankruptcy_ms" => nil
    })
    |> EntityIndex.rebuild()
  end

  defp action(state, kind \\ "sale", amount \\ 10_000) do
    changed =
      Journal.post(state, "c", kind, [{"sales_revenue", -amount}, {"cash_available", amount}])

    InvitationAccrual.observe(state, changed, %{}) |> Journal.clear()
  end

  defp tick(state, now) do
    next = InvitationAccrual.observe(state, %{state | clock_ms: now}, %{}, :all)
    assert :ok == ChangeSet.assert_complete!(state, next)
    next
  end

  defp quota(state), do: State.get(state, "accounts", "a")["invite_quota"]
  defp progress(state), do: State.get(state, "invitation_progress", "a")["progress_ms"]

  defp forecast(state),
    do: InvitationAccrual.forecast(state, State.get(state, "accounts", "a"))

  test "forecasts use saved world-clock progress without granting invitations" do
    assert forecast(world())["status"] == "inactive"
    state = world() |> action() |> tick(@day)
    assert forecast(state) == %{"status" => "earning", "remaining_ms" => @day, "refund_ms" => nil}
    projected = %{state | clock_ms: @day + 1000}
    assert forecast(projected)["remaining_ms"] == @day - 1000
    assert quota(projected) == 0
    assert progress(projected) == @day
  end

  test "inactive and replaced companies cannot project stale partial progress" do
    state = world() |> action() |> tick(@day)
    assert forecast(%{state | clock_ms: 3 * @day})["remaining_ms"] == 2 * @day
    assert forecast(%{state | clock_ms: 3 * @day})["status"] == "inactive"

    replacement =
      state
      |> State.put("companies", "new", Map.put(State.get(state, "companies", "c"), "id", "new"))
      |> State.put(
        "accounts",
        "a",
        Map.put(State.get(state, "accounts", "a"), "company_id", "new")
      )

    assert forecast(replacement)["status"] == "inactive"
    assert forecast(replacement)["remaining_ms"] == 2 * @day
  end

  test "forecast identifies missing company, suspension and financial blocks" do
    state = world() |> action()

    for {kind, id, key, value, expected} <- [
          {"accounts", "a", "company_id", nil, "no_company"},
          {"accounts", "a", "suspended_ms", 0, "suspended"},
          {"companies", "c", "bankruptcy_ms", 0, "no_company"},
          {"companies", "c", "unpaid", 1, "financial_trouble"},
          {"companies", "c", "arrears_since", 0, "financial_trouble"}
        ] do
      changed = State.put(state, kind, id, Map.put(State.get(state, kind, id), key, value))
      assert forecast(changed)["status"] == expected
    end

    loan = %{
      "company_id" => "c",
      "status" => "open",
      "principal_due" => 0,
      "interest_due" => 1,
      "overdue_ms" => nil
    }

    assert forecast(State.put(state, "loans", "loan", loan))["status"] == "financial_trouble"

    assert forecast(State.put(state, "loans", "loan", Map.put(loan, "interest_due", 0)))["status"] ==
             "earning"
  end

  test "forecast counts only the owner's outstanding invitations and exposes earliest refund" do
    state = world(3) |> action()

    state =
      Enum.reduce(1..3, state, fn n, state ->
        {:ok, state, _} =
          AccountWorld.issue_invite(state, State.get(state, "accounts", "a"), %{
            invite_hash: "code-#{n}"
          })

        state
      end)

    first = Map.put(State.get(state, "invitations", "code-1"), "expires_ms", @day)
    state = State.put(state, "invitations", "code-1", first)
    state = State.put(state, "invitations", "other", Map.put(first, "inviter", "other"))

    assert forecast(state) == %{
             "status" => "capacity",
             "remaining_ms" => 2 * @day,
             "refund_ms" => @day
           }

    state = State.put(state, "invitations", "code-1", Map.put(first, "status", "redeemed"))
    assert forecast(state)["status"] == "earning"
    assert forecast(state)["refund_ms"] == 3 * @day
  end

  test "ordinary players earn exactly at two days and splitting ticks preserves the award" do
    state = world() |> action()
    early = tick(state, 2 * @day - 1)
    assert quota(early) == 0
    assert State.entities(early, "notices") == %{}
    assert progress(early) == 2 * @day - 1
    awarded = tick(early, 2 * @day)
    assert quota(awarded) == 1
    assert progress(awarded) == 0
    assert [notice] = State.owned(awarded, "notices", "account_id", "a")
    assert notice["code"] == "invitation.earned"
    assert notice["clock_ms"] == 2 * @day
    assert tick(awarded, 2 * @day).entities["notices"] == awarded.entities["notices"]
    assert quota(tick(awarded, 2 * @day)) == 1
    assert tick(state, 2 * @day).entities == awarded.entities
    assert InvitationProgress.period_ms() == 2 * @day
  end

  test "world-clock pauses, sign-ins and insignificant actions do not earn invitations" do
    state = world()
    assert quota(tick(state, 100 * @day)) == 0
    refute State.get(action(state, "loan_draw"), "invitation_progress", "a")
    refute State.get(action(state, "sale", 9999), "invitation_progress", "a")
    active = action(state)
    assert tick(active, 0) == active
    assert quota(tick(active, 10 * @day)) == 1
    assert quota(tick(tick(active, 10 * @day), 20 * @day)) == 1
  end

  test "continued qualifying activity earns repeatedly while gaps discard partial progress" do
    state = world() |> action() |> tick(@day) |> action()
    state = tick(state, 2 * @day) |> action() |> tick(3 * @day) |> action()
    awarded = tick(state, 4 * @day)
    assert quota(awarded) == 2

    assert Enum.map(State.owned(awarded, "notices", "account_id", "a"), & &1["clock_ms"])
           |> Enum.sort() == [2 * @day, 4 * @day]

    # Three active days earn one invitation, but the partial third day cannot
    # survive a gap and combine with an unrelated later activity window.
    gap = world() |> action() |> tick(@day) |> action() |> tick(4 * @day) |> action()
    assert quota(gap) == 1
    assert progress(gap) == 0
    assert quota(tick(gap, 5 * @day)) == 1
    assert quota(tick(tick(gap, 5 * @day), 6 * @day)) == 2
  end

  test "unpaid bills, loan arrears and suspension reset progress" do
    state = world() |> action() |> tick(@day)

    for {kind, id, row} <- [
          {"companies", "c", Map.put(State.get(state, "companies", "c"), "unpaid", 100)},
          {"companies", "c", Map.put(State.get(state, "companies", "c"), "arrears_since", @day)},
          {"accounts", "a", Map.put(State.get(state, "accounts", "a"), "suspended_ms", @day)},
          {"loans", "l",
           %{
             "company_id" => "c",
             "status" => "open",
             "principal_due" => 100,
             "interest_due" => 0,
             "overdue_ms" => nil
           }},
          {"loans", "l",
           %{
             "company_id" => "c",
             "status" => "open",
             "principal_due" => 0,
             "interest_due" => 100,
             "overdue_ms" => nil
           }}
        ] do
      troubled = State.put(state, kind, id, row)
      troubled = InvitationAccrual.observe(state, troubled, %{})
      assert progress(troubled) == 0
      assert quota(tick(troubled, 2 * @day)) == 0
      assert :ok == ChangeSet.assert_complete!(state, troubled)
    end
  end

  test "clearing a bill resumes from zero and company replacement discards old activity" do
    state = world() |> action() |> tick(@day)
    company = State.get(state, "companies", "c")
    bad = State.put(state, "companies", "c", Map.put(company, "unpaid", 100))
    bad = InvitationAccrual.observe(state, bad, %{}) |> tick(2 * @day)
    recovered = State.put(bad, "companies", "c", company)
    recovered = InvitationAccrual.observe(bad, recovered, %{}) |> action()
    assert quota(tick(recovered, 3 * @day)) == 0
    assert quota(tick(tick(recovered, 3 * @day), 4 * @day)) == 1

    account = State.get(state, "accounts", "a")
    closed = State.put(state, "accounts", "a", Map.put(account, "company_id", nil))
    closed = InvitationAccrual.observe(state, closed, %{})
    assert progress(closed) == 0

    replacement =
      closed
      |> State.put("companies", "new", Map.put(company, "id", "new"))
      |> State.put("accounts", "a", Map.put(account, "company_id", "new"))

    replacement = InvitationAccrual.observe(closed, replacement, %{})
    assert quota(tick(replacement, 10 * @day)) == 0
    assert State.get(replacement, "invitation_progress", "a")["company_id"] == "new"
  end

  test "available plus outstanding quota is capped and expiry refunds without minting more" do
    state = world(2) |> action() |> tick(2 * @day)
    assert quota(state) == 3
    state = action(state) |> tick(4 * @day)
    assert quota(state) == 3
    assert length(State.owned(state, "notices", "account_id", "a")) == 1

    {:ok, issued, _} =
      AccountWorld.issue_invite(state, State.get(state, "accounts", "a"), %{invite_hash: "code"})

    issued = action(issued) |> tick(6 * @day)
    assert quota(issued) == 2
    expired = AccountWorld.expire_invitations(%{issued | clock_ms: 7 * @day})
    assert quota(expired) == 3
    assert quota(tick(expired, 7 * @day)) == 3
    assert tick(expired, 7 * @day).entities["notices"] == state.entities["notices"]
  end

  test "a redeemed invitation frees capacity without banking time spent at the cap" do
    state = world(3) |> action() |> tick(2 * @day) |> action()

    {:ok, state, _} =
      AccountWorld.issue_invite(state, State.get(state, "accounts", "a"), %{invite_hash: "code"})

    {:ok, redeemed, _} =
      AccountWorld.redeem(state, "code", "device", %{id: "invitee", wall_ms: 0})

    assert State.get(redeemed, "accounts", "invitee")["invite_quota"] == 0
    assert quota(tick(redeemed, 3 * @day)) == 2
    assert quota(tick(tick(redeemed, 3 * @day), 4 * @day)) == 3
  end

  test "automated economic events activate only their owner's company" do
    state =
      world()
      |> State.put("accounts", "other", Account.Rows.encode(Account.new("other", nil, false, 0)))

    active = action(state, "exchange_sale") |> tick(2 * @day)
    assert quota(active) == 1
    assert State.get(active, "accounts", "other")["invite_quota"] == 0
    refute State.get(active, "invitation_progress", "other")
  end
end
