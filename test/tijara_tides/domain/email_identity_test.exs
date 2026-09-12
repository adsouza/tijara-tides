defmodule TijaraTides.Domain.EmailIdentityTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{Account, EmailIdentity, Game, Visibility}

  setup do
    state = %{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}
    {:ok, state, _} = Account.seed_invite(state, "seed")
    {:ok, state, _} = Account.redeem(state, "seed", "original", %{id: "sponsor", wall_ms: 0})
    %{state: state, account: Game.get(state, "accounts", "sponsor")}
  end

  defp context(id, wall \\ 100),
    do: %{id: id, hash: id <> "-hash", requester: "requester", wall_ms: wall}

  test "link requires possession, normalizes email, and permits same-device retry only", c do
    {:ok, state, result} =
      EmailIdentity.request(c.state, c.account, "link", " Player@Example.com ", context("link"))

    assert result == %{"requested" => true}
    assert Game.get(state, "accounts", "sponsor")["email"] == nil
    {:ok, state, _} = EmailIdentity.redeem(state, "link-hash", "device", nil, context("verify"))
    assert Game.get(state, "accounts", "sponsor")["email"] == "player@example.com"
    assert {:ok, _, _} = EmailIdentity.redeem(state, "link-hash", "device", nil, context("retry"))

    assert {:error, :email_link_invalid} =
             EmailIdentity.redeem(state, "link-hash", "other", nil, context("retry"))

    assert {:ok, _} = Account.authenticate(state, "original", 100)
    assert {:ok, _} = Account.authenticate(state, "device", 100)
  end

  test "emailed invitation links atomically and cannot be redeemed as an unlinked code", c do
    {:ok, state, _} =
      EmailIdentity.request(c.state, c.account, "invite", "new@example.com", context("invite"))

    assert Game.get(state, "accounts", "sponsor")["invite_quota"] == 2

    assert {:error, :invalid_invitation} =
             Account.redeem(state, "invite-hash", "bypass", context("new"))

    assert {:error, :email_wrong_account} =
             EmailIdentity.redeem(state, "invite-hash", "device", c.account, context("new"))

    {:ok, state, _} = EmailIdentity.redeem(state, "invite-hash", "device", nil, context("new"))
    assert Game.get(state, "accounts", "new")["email"] == "new@example.com"
    assert Game.get(state, "accounts", "new")["inviter"] == "sponsor"

    assert {:error, :email_unavailable} =
             EmailIdentity.request(
               state,
               c.account,
               "invite",
               "NEW@example.com",
               context("duplicate")
             )

    private = Visibility.private(state, Game.get(state, "accounts", "sponsor"))
    refute inspect(private) =~ "invite-hash"
  end

  test "expired invite restores quota and expiry uses the active clock", c do
    {:ok, state, _} =
      EmailIdentity.request(c.state, c.account, "invite", "new@example.com", context("invite"))

    # Long wall-clock suspension does not age invitations.
    assert {:ok, _, _} =
             EmailIdentity.redeem(
               state,
               "invite-hash",
               "device",
               nil,
               context("new", 999_999_999)
             )

    expired = %{state | clock_ms: 3 * 86_400_000}

    assert {:error, :email_link_invalid} =
             EmailIdentity.redeem(expired, "invite-hash", "device", nil, context("new"))

    expired = Account.expire_invitations(expired)
    assert Game.get(expired, "accounts", "sponsor")["invite_quota"] == 3
  end

  test "email sign-in restores identity and old address links stop working after replacement",
       c do
    {:ok, state, _} =
      EmailIdentity.request(c.state, c.account, "link", "old@example.com", context("link"))

    {:ok, state, _} = EmailIdentity.redeem(state, "link-hash", "linked", nil, context("v"))

    {:ok, state, _} =
      EmailIdentity.request(state, nil, "login", "old@example.com", context("login"))

    {:ok, state, _} = EmailIdentity.redeem(state, "login-hash", "new-device", nil, context("v"))
    assert {:ok, %{"id" => "sponsor"}} = Account.authenticate(state, "new-device", 100)

    {:ok, state, _} =
      EmailIdentity.request(state, nil, "login", "old@example.com", context("old-login"))

    {:ok, state, _} =
      EmailIdentity.request(state, c.account, "link", "new@example.com", context("new-link"))

    assert Game.get(state, "accounts", "sponsor")["email"] == "old@example.com"
    {:ok, state, _} = EmailIdentity.redeem(state, "new-link-hash", "new-email", nil, context("v"))

    assert {:error, :email_link_invalid} =
             EmailIdentity.redeem(state, "old-login-hash", "bad", nil, context("v"))
  end

  test "unknown addresses are indistinguishable in response but never sent or redeemable", c do
    {:ok, state, result} =
      EmailIdentity.request(c.state, nil, "login", "unknown@example.com", context("unknown"))

    assert result == %{"requested" => true}
    assert Game.get(state, "email_requests", "unknown")["delivery"] == "ignored"

    assert {:error, :email_link_invalid} =
             EmailIdentity.redeem(state, "unknown-hash", "device", nil, context("v"))
  end

  test "validation, wall-clock expiry, throttling, and delivery backoff", c do
    for email <- [nil, <<255>>, "bad", "a\nb@example.com", String.duplicate("a", 255) <> "@x.com"] do
      assert {:error, :email_invalid} =
               EmailIdentity.request(c.state, c.account, "link", email, context("bad"))
    end

    assert {:error, :invalid_session} =
             EmailIdentity.request(c.state, nil, "invite", "a@example.com", context("bad"))

    {:ok, state, _} =
      EmailIdentity.request(c.state, c.account, "link", "a@example.com", context("one"))

    assert {:error, :email_link_invalid} =
             EmailIdentity.redeem(state, "one-hash", "device", nil, context("v", 900_100))

    state =
      Enum.reduce(2..3, state, fn i, state ->
        {:ok, next, _} =
          EmailIdentity.request(state, c.account, "link", "a@example.com", context("#{i}"))

        next
      end)

    assert {:error, :email_rate_limited} =
             EmailIdentity.request(state, c.account, "link", "a@example.com", context("four"))

    state = EmailIdentity.delivery_failed(state, Game.get(state, "email_requests", "one"), 100)
    assert Game.get(state, "email_requests", "one")["retry_ms"] == 60_100

    state =
      Enum.reduce(1..7, state, fn _, state ->
        EmailIdentity.delivery_failed(state, Game.get(state, "email_requests", "one"), 100)
      end)

    assert Game.get(state, "email_requests", "one")["delivery"] == "failed"
  end
end
