defmodule TijaraTides.Infrastructure.GameServerFailuresTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  alias TijaraTides.Domain.{Game, Journal}
  alias TijaraTides.Infrastructure.GameServer
  alias TijaraTides.UseCases.WorldProjection

  # Narrow persistence doubles exercise the callback's failure contract without
  # introducing production injection hooks or changing a real database.
  defmodule RejectCommit do
    def transaction(_fun), do: {:ok, %{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}}
    def transaction(_fun, _opts), do: {:error, :ownership_lost}
  end

  defmodule StorageException do
    def transaction(_fun),
      do:
        raise(DBConnection.ConnectionError,
          message: "Connection refused password=private-db-marker"
        )

    def query!(_sql, _args),
      do:
        raise(DBConnection.ConnectionError,
          message: "Connection refused password=private-db-marker"
        )
  end

  defmodule DomainException do
    def query!(_sql, _args),
      do: raise(ArgumentError, "Invalid command token=private-domain-marker")
  end

  defmodule NoPersistence do
    def transaction(_, _) do
      send(self(), :unexpected_persistence)
      raise "a failing domain tick attempted persistence"
    end
  end

  setup do
    {:ok, state} = GameServer.init(enabled: false)
    game = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, state.catalogue)
    {:ok, game, _} = Game.seed_invite(game, "invite")

    {:ok, game, _} =
      Game.redeem(game, "invite", GameServer.hash("token"), %{
        id: "account",
        wall_ms: System.system_time(:millisecond)
      })

    game = Journal.clear(game)

    state = %{
      state
      | game: game,
        projection: WorldProjection.build(game, state.catalogue),
        status: :ready,
        active: true
    }

    GameServer.subscribe()
    %{state: state}
  end

  test "startup refuses a failed initial commit and does not expose the candidate world" do
    assert {:ok, state} = GameServer.init(enabled: true, repo: RejectCommit)
    assert state.status == :unavailable
    assert state.game == nil
    assert state.projection == nil
    refute state.active
  end

  test "startup exceptions are contained and logged without connection details" do
    log =
      capture_log(fn ->
        assert {:ok, state} = GameServer.init(enabled: true, repo: StorageException)
        assert state.status == :unavailable
        assert state.game == nil
        refute state.active
      end)

    assert log =~ "initialization"
    assert log =~ "DBConnection.ConnectionError"
    assert log =~ "Connection refused password=[REDACTED]"
    refute log =~ "private-db-marker"
  end

  for {repo, error, marker} <- [
        {StorageException, :storage_unavailable, "private-db-marker"},
        {DomainException, :internal_error, "private-domain-marker"}
      ] do
    test "command exception #{error} pauses the owner without publishing or advancing state", %{
      state: state
    } do
      state = %{state | repo: unquote(repo)}

      log =
        capture_log(fn ->
          assert {:reply, {:error, unquote(error)}, next} =
                   GameServer.handle_call(
                     {:command, "token", "request", %{"action" => "invite"}},
                     nil,
                     state
                   )

          assert next.game == state.game
          assert next.projection == state.projection
          assert next.status == :unavailable
          refute next.active

          assert {:reply, {:error, :unavailable}, ^next} =
                   GameServer.handle_call({:command, "token", "again", %{}}, nil, next)
        end)

      assert log =~ "command"
      assert log =~ "[REDACTED]"
      refute log =~ unquote(marker)
      refute_receive {:game_changed, _}, 10
    end
  end

  test "a rejected tick commit preserves the previous clock and projection", %{state: state} do
    state = %{state | repo: RejectCommit, last_mono: System.monotonic_time(:millisecond) - 5000}

    log =
      capture_log(fn ->
        assert {:noreply, next} = GameServer.handle_info(:tick, state)
        assert next.status == :unavailable
        refute next.active
        assert next.game == state.game
        assert next.projection == state.projection
        assert {:noreply, ^next} = GameServer.handle_info(:tick, next)
      end)

    assert log =~ "ownership_lost"
    refute_receive {:game_changed, _}, 10
  end

  test "a domain exception during progression never reaches persistence", %{state: state} do
    state = %{state | repo: NoPersistence, game: %{state.game | clock_ms: :invalid_clock}}

    log =
      capture_log(fn ->
        assert {:noreply, next} = GameServer.handle_info(:tick, state)
        assert next.status == :unavailable
        refute next.active
        assert next.game == state.game
        assert next.projection == state.projection
      end)

    refute_receive :unexpected_persistence, 10
    assert log =~ "progression"
    refute_receive {:game_changed, _}, 10
  end

  test "an invalid connection cannot activate an idle world", %{state: state} do
    state = %{state | active: false}

    assert {:reply, {:error, :invalid_session}, ^state} =
             GameServer.handle_call({:connect, "invalid"}, nil, state)
  end
end
