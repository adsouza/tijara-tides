defmodule TijaraTides.UseCases.GameCommandsTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.Game
  alias TijaraTides.Infrastructure.GameCatalogue
  alias TijaraTides.UseCases.{CommandRequest, GameCommands, WorldProjection, GameQueries}

  defmodule Store do
    @behaviour TijaraTides.UseCases.CommandStore
    def receipt(ops, account, id, fingerprint), do: ops.receipt.(account, id, fingerprint)
    def commit(ops, before, changed, receipt), do: ops.commit.(before, changed, receipt)
    def restore(_ops, game, _operation), do: game
  end

  setup do
    catalogue = GameCatalogue.all()
    game = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, catalogue)
    {:ok, game, _} = Game.seed_invite(game, "invite")
    {:ok, game, _} = Game.redeem(game, "invite", "session", %{id: "account", wall_ms: 0})
    game = TijaraTides.Domain.Journal.clear(game)

    request = %CommandRequest{
      id: "request",
      fingerprint: "fingerprint",
      payload: %{
        "action" => "company",
        "name" => "Voyager",
        "port" => "Jakarta",
        "package" => "general"
      }
    }

    context = %{id: "company", wall_ms: 1, catalogue: catalogue}
    invitation = fn _, _ -> %{hash: "derived-invite", decorate: & &1} end
    %{game: game, request: request, context: context, invitation: invitation}
  end

  test "commits empty company and receipt before exposing a clean result", c do
    ops = %{
      receipt: fn "account", "request", "fingerprint" -> :new end,
      commit: fn before, changed, receipt ->
        assert before == c.game
        assert changed.revision == before.revision + 1
        assert Map.get(changed, :journal, []) == []
        assert changed.entities["companies"]["company"]["cash"] == 0
        assert receipt == {"account", "request", "fingerprint", %{"company_id" => "company"}}
        send(self(), :committed)
        {:ok, :ok}
      end
    }

    assert {:ok, result} = run(c, ops)
    assert_received :committed
    assert result.committed?
    refute Map.has_key?(result.game, :journal)
    projection = WorldProjection.build(result.game, c.context.catalogue)
    assert projection.revision == result.game.revision
    assert projection.public["companies"]["company"]["name"] == "Voyager"
    refute Map.has_key?(projection.public, "sessions")

    assert GameQueries.snapshot(
             result.game,
             c.context.catalogue,
             projection,
             {:error, :invalid_session}
           ).private == nil
  end

  test "both replay paths decorate the persisted result without a new publication", c do
    c = %{c | invitation: fn _, _ -> %{hash: "new", decorate: &Map.put(&1, "code", "legacy")} end}
    persisted = %{"invitation" => "old"}

    for path <- [:outer, :transaction] do
      ops = %{
        receipt: fn _, _, _ -> if path == :outer, do: {:replay, persisted}, else: :new end,
        commit: fn _, _, _ ->
          assert path == :transaction
          {:error, {:replay, persisted}}
        end
      }

      assert {:ok, result} = run(c, ops)
      refute result.committed?
      assert result.game == c.game
      assert result.reply == %{"invitation" => "old", "code" => "legacy"}
    end
  end

  test "business failures never commit; persistence failures halt without exposing changed state",
       c do
    no_commit = %{
      receipt: fn _, _, _ -> :new end,
      commit: fn _, _, _ -> flunk("unexpected commit") end
    }

    invalid = %{c | request: %{c.request | payload: Map.put(c.request.payload, "name", "")}}
    assert {:error, :invalid_name} = run(invalid, no_commit)

    assert {:error, :invalid_session} =
             GameCommands.run(
               c.game,
               "wrong",
               c.request,
               c.context,
               {Store, no_commit},
               c.invitation
             )

    failed = %{no_commit | commit: fn _, _, _ -> {:error, :ownership_lost} end}
    assert {:halt, :ownership_lost} = run(c, failed)
  end

  test "payload validation distinguishes shape, key count, size and expired session", c do
    no_access = %{
      receipt: fn _, _, _ -> flunk("validation reached persistence") end,
      commit: fn _, _, _ -> flunk("validation reached commit") end
    }

    no_invitation = fn _, _ -> flunk("validation reached credential derivation") end

    for {payload, reason} <- [
          {nil, :invalid_command_payload},
          {Map.new(1..13, &{to_string(&1), 0}), :too_many_command_fields},
          {%{"name" => String.duplicate("x", 4096)}, :command_payload_too_large}
        ] do
      invalid = %{c | request: %{c.request | payload: payload}, invitation: no_invitation}
      assert {:error, ^reason} = run(invalid, no_access)
      message = TijaraTidesWeb.GameLive.error_message(reason)
      refute message =~ "session"
      refute message =~ "could not be completed"
    end

    expired = %{c | context: %{c.context | wall_ms: 366 * 86_400_000}, invitation: no_invitation}
    assert {:error, :invalid_session} = run(expired, no_access)
  end

  defp run(c, ops),
    do: GameCommands.run(c.game, "session", c.request, c.context, {Store, ops}, c.invitation)
end
