defmodule TijaraTides.Domain.AccountAggregateTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.Account
  alias Account.EmailIdentity

  defp row(id \\ "a") do
    %{
      "id" => id,
      "company_id" => nil,
      "inviter" => "sponsor",
      "bankruptcies" => 0,
      "suspended_ms" => nil,
      "email" => nil,
      "invite_quota" => 3,
      "created_ms" => 0
    }
  end

  defp world do
    %{clock_ms: 0, entities: %{"accounts" => %{"a" => row(), "b" => row("b")}}}
  end

  test "stale account snapshots cannot restore spent invitation quota; expiry refunds once" do
    state = world()
    {:ok, state, _} = Account.issue_invite(state, row(), %{invite_hash: "one"})
    {:ok, state, _} = Account.issue_invite(state, row(), %{invite_hash: "two"})
    {:ok, state, _} = Account.issue_invite(state, row(), %{invite_hash: "three"})

    assert {:error, :no_invitation_quota} =
             Account.issue_invite(state, row(), %{invite_hash: "four"})

    assert Account.from_world(state, "a").invite_quota == 0
    state = Account.expire_invitations(%{state | clock_ms: 3 * 86_400_000})
    assert Account.from_world(state, "a").invite_quota == 3
    assert Account.expire_invitations(state) == state
  end

  test "company association is exclusive and bankruptcy history cannot be counted twice" do
    state = world()
    company = %{"id" => "c", "account_id" => "a", "bankruptcy_ms" => nil}
    state = put_in(state.entities["companies"], %{"c" => company})
    state = Account.attach_company(state, "a", "c")
    assert_raise ArgumentError, fn -> Account.attach_company(state, "a", "c") end
    assert_raise ArgumentError, fn -> Account.attach_company(state, "b", "c") end
    state = put_in(state.entities["companies"]["c"]["bankruptcy_ms"], 0)
    state = Account.record_bankruptcy(state, "a", "c", "voluntary", 1_200_000)
    assert Account.from_world(state, "a").company_id == nil
    assert Account.counted(state, row()) == 1
    assert Account.restart_at(state, row()) == 1_200_000

    assert_raise ArgumentError, fn ->
      Account.record_bankruptcy(state, "a", "c", "voluntary", 1_200_000)
    end

    assert Account.counted(%{state | clock_ms: Account.history_ms()}, row()) == 0
    assert Account.from_world(state, "a").bankruptcies == 1
  end

  test "verified identities and device sessions cannot be reassigned to a different account" do
    state = Account.verify_email(world(), "a", "one@example.com", "device", 1000)

    assert_raise ArgumentError, fn ->
      Account.verify_email(state, "b", "one@example.com", "other-device", 1000)
    end

    assert_raise ArgumentError, fn ->
      Account.verify_email(state, "b", "two@example.com", "device", 1000)
    end

    assert {:ok, %{"id" => "a"}} = Account.authenticate(state, "device", 999)
    assert {:error, :invalid_session} = Account.authenticate(state, "device", 1000)

    assert Account.sign_out(state, "device") |> Account.authenticate("device", 0) ==
             {:error, :invalid_session}
  end

  test "only a funded pledge by the original sponsor can reinstate an account" do
    state = put_in(world().entities["accounts"]["a"]["suspended_ms"], 0)
    assert_raise ArgumentError, fn -> Account.reinstate(state, "a", "missing") end

    pledge = %{
      "sponsor_id" => "other",
      "beneficiary_id" => "a",
      "status" => "pledged",
      "amount" => 5_000_000
    }

    state = put_in(state.entities["guarantees"], %{"g" => pledge})
    assert_raise ArgumentError, fn -> Account.reinstate(state, "a", "g") end
    state = put_in(state.entities["guarantees"]["g"]["sponsor_id"], "sponsor")

    assert Account.reinstate(state, "a", "g") |> Account.from_world("a") |> Account.suspended?() ==
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
