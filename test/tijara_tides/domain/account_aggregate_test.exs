defmodule TijaraTides.Domain.AccountAggregateTest do
  alias TijaraTides.Domain.AccountWorld
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.Account
  alias TijaraTides.Domain.AccountWorld.EmailIdentity

  defp row(id \\ "a") do
    %{
      "id" => id,
      "company_id" => nil,
      "inviter" => "sponsor",
      "bankruptcies" => 0,
      "suspended_ms" => nil,
      "email" => nil,
      "invite_quota" => 3,
      "created_ms" => 0,
      "locale" => "en"
    }
  end

  defp world do
    %{clock_ms: 0, entities: %{"accounts" => %{"a" => row(), "b" => row("b")}}}
  end

  test "grant includes pending invitations, preserves identity and discards progress at capacity" do
    alias TijaraTides.Domain.{ChangeSet, State}
    progress = TijaraTides.Domain.Account.InvitationProgress.new("a", "company", 0)
    progress = %{progress | "progress_ms" => 100, "active_until_ms" => 200}

    state =
      world()
      |> State.put("accounts", "a", %{row() | "invite_quota" => 0})
      |> State.put("invitation_progress", "a", progress)

    state = %{state | clock_ms: 100}
    {:ok, changed, result} = AccountWorld.grant_invitations(state, "a", 3)
    assert result["quota_after"] == 3

    assert changed.entities["accounts"]["a"] ==
             Map.put(row(), "invite_quota", 3) |> Map.put("funding_policy", "wait")

    assert changed.entities["accounts"]["b"] == state.entities["accounts"]["b"]
    assert changed.entities["invitation_progress"]["a"]["progress_ms"] == 0
    assert changed.entities["invitation_progress"]["a"]["checked_ms"] == state.clock_ms
    assert changed.entities["invitation_progress"]["a"]["active_until_ms"] == 200
    assert :ok == ChangeSet.assert_complete!(state, changed)

    assert Map.keys(ChangeSet.since(state, changed)) |> Enum.sort() ==
             [{"accounts", "a"}, {"invitation_progress", "a"}]

    {:ok, issued, _} = AccountWorld.issue_invite(changed, row(), %{invite_hash: "pending"})
    assert {:error, :invitation_capacity} = AccountWorld.grant_invitations(issued, "a", 1)
    assert {:error, :account_not_found} = AccountWorld.grant_invitations(state, "absent", 1)
  end

  test "stale account snapshots cannot restore spent invitation quota; expiry refunds once" do
    state = world()
    {:ok, state, _} = AccountWorld.issue_invite(state, row(), %{invite_hash: "one"})
    {:ok, state, _} = AccountWorld.issue_invite(state, row(), %{invite_hash: "two"})
    {:ok, state, _} = AccountWorld.issue_invite(state, row(), %{invite_hash: "three"})

    assert {:error, :no_invitation_quota} =
             AccountWorld.issue_invite(state, row(), %{invite_hash: "four"})

    assert AccountWorld.fetch(state, "a").invite_quota == 0
    state = AccountWorld.expire_invitations(%{state | clock_ms: 3 * 86_400_000})
    assert AccountWorld.fetch(state, "a").invite_quota == 3
    assert AccountWorld.expire_invitations(state) == state
  end

  test "company association is exclusive and bankruptcy history cannot be counted twice" do
    state = world()
    company = %{"id" => "c", "account_id" => "a", "bankruptcy_ms" => nil}
    state = put_in(state.entities["companies"], %{"c" => company})
    state = AccountWorld.attach_company(state, "a", "c")
    assert_raise ArgumentError, fn -> AccountWorld.attach_company(state, "a", "c") end
    assert_raise ArgumentError, fn -> AccountWorld.attach_company(state, "b", "c") end
    state = put_in(state.entities["companies"]["c"]["bankruptcy_ms"], 0)
    state = AccountWorld.record_bankruptcy(state, "a", "c", "voluntary", 1_200_000)
    assert AccountWorld.fetch(state, "a").company_id == nil
    assert AccountWorld.counted(state, row()) == 1
    assert AccountWorld.restart_at(state, row()) == 180_000

    assert_raise ArgumentError, fn ->
      AccountWorld.record_bankruptcy(state, "a", "c", "voluntary", 1_200_000)
    end

    assert AccountWorld.counted(%{state | clock_ms: Account.history_ms()}, row()) == 0
    assert AccountWorld.fetch(state, "a").bankruptcies == 1
  end

  test "verified identities and device sessions cannot be reassigned to a different account" do
    state = AccountWorld.verify_email(world(), "a", "one@example.com", "device", 1000)

    assert_raise ArgumentError, fn ->
      AccountWorld.verify_email(state, "b", "one@example.com", "other-device", 1000)
    end

    assert_raise ArgumentError, fn ->
      AccountWorld.verify_email(state, "b", "two@example.com", "device", 1000)
    end

    assert {:ok, %{"id" => "a"}} = AccountWorld.authenticate(state, "device", 999)
    assert {:error, :invalid_session} = AccountWorld.authenticate(state, "device", 1000)

    assert AccountWorld.sign_out(state, "device") |> AccountWorld.authenticate("device", 0) ==
             {:error, :invalid_session}
  end

  test "only a funded pledge by the original sponsor can reinstate an account" do
    state = put_in(world().entities["accounts"]["a"]["suspended_ms"], 0)
    assert_raise ArgumentError, fn -> AccountWorld.reinstate(state, "a", "missing") end

    pledge = %{
      "sponsor_id" => "other",
      "beneficiary_id" => "a",
      "status" => "pledged",
      "amount" => 5_000_000
    }

    state = put_in(state.entities["guarantees"], %{"g" => pledge})
    assert_raise ArgumentError, fn -> AccountWorld.reinstate(state, "a", "g") end
    state = put_in(state.entities["guarantees"]["g"]["sponsor_id"], "sponsor")

    assert AccountWorld.reinstate(state, "a", "g")
           |> AccountWorld.fetch("a")
           |> AccountWorld.suspended?() ==
             false
  end

  test "delivery acknowledgements preserve credential redemption performed after dispatch" do
    old = %{"id" => "r", "delivery" => "pending", "used_session" => nil}

    state =
      put_in(world().entities["email_requests"], %{"r" => %{old | "used_session" => "device"}})

    state = EmailIdentity.delivered(state, old)
    assert state.entities["email_requests"]["r"]["used_session"] == "device"
    assert state.entities["email_requests"]["r"]["delivery"] == "sent"
  end
end
