defmodule TijaraTides.UseCases.AuthenticationTest do
  use ExUnit.Case, async: true
  alias TijaraTides.UseCases.{Authentication, LifecycleCommands, ReportQueries}

  defmodule Store do
    def restore(_, game, _), do: game
    def commit(ops, before, changed, receipt), do: ops.commit.(before, changed, receipt)
    def reload(ops, game), do: ops.reload.(game)
  end

  setup do
    account = %{"id" => "a", "company_id" => nil, "email" => nil}

    game = %{
      entities: %{
        "accounts" => %{"a" => account},
        "sessions" => %{"session" => %{"account_id" => "a", "expires_at" => 100}}
      },
      clock_ms: 0,
      epoch: 1,
      revision: 0
    }

    %{game: game, account: account}
  end

  test "required and optional authentication share the exact expiry boundary", c do
    assert Authentication.required(c.game, "session", 99) == {:ok, c.account}
    assert Authentication.optional(c.game, "session", 99) == c.account

    for credential <- ["session", "missing", nil, %{}] do
      assert Authentication.required(c.game, credential, 100) == {:error, :invalid_session}
      assert Authentication.optional(c.game, credential, 100) == nil
    end

    deleted = put_in(c.game, [:entities, "accounts"], %{})
    assert Authentication.required(deleted, "session", 99) == {:error, :invalid_session}
  end

  test "public reports drop owner access at session expiry", c do
    assert ReportQueries.plan(c.game, "session", 99, %{}).owner == "a"
    assert ReportQueries.plan(c.game, "session", 100, %{}).owner == nil
  end

  test "email linking reauthenticates after conflict reload", c do
    revoked = TijaraTides.Domain.Account.sign_out(c.game, "session")

    ops = %{
      commit: fn _, changed, _ ->
        row = changed.entities["email_requests"]["request"]
        assert row["account_id"] == "a"
        assert row["requester"] == :crypto.hash(:sha256, "a") |> Base.encode16(case: :lower)
        send(self(), :commit_attempt)
        {:error, :market_conflict}
      end,
      reload: fn _ -> {:ok, revoked} end
    }

    context = %{id: "request", hash: "email-token", requester: "anonymous-key", wall_ms: 99}

    assert {:error, :invalid_session, _} =
             LifecycleCommands.run(
               c.game,
               {:email_request, "session", "link", "player@example.test"},
               context,
               {Store, ops}
             )

    assert_received :commit_attempt
    refute_received :commit_attempt
  end

  test "an expired session can request login but cannot link or invite", c do
    context = %{id: "request", hash: "email-token", requester: "anonymous-key", wall_ms: 100}

    ops = %{
      commit: fn _, changed, _ ->
        row = changed.entities["email_requests"]["request"]
        assert row["account_id"] == nil
        assert row["requester"] == "anonymous-key"
        {:ok, :ok}
      end
    }

    assert {:ok, _} =
             LifecycleCommands.run(
               c.game,
               {:email_request, "session", "login", "player@example.test"},
               context,
               {Store, ops}
             )

    for purpose <- ["link", "invite"] do
      assert {:error, :invalid_session} =
               LifecycleCommands.run(
                 c.game,
                 {:email_request, "session", purpose, "player@example.test"},
                 context,
                 {Store, ops}
               )
    end
  end
end
