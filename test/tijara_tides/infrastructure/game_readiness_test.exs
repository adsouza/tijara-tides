defmodule TijaraTides.Infrastructure.GameReadinessTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Infrastructure.{GameReadiness, GameServer, OperationBoundary}

  test "readiness remains immediate while the actual owner is suspended" do
    server = start_supervised!({GameServer, name: nil, enabled: false})
    :ok = :sys.suspend(server)

    try do
      task = Task.async(fn -> GameServer.readiness(server) end)
      assert Task.await(task, 500) == :not_configured
    after
      :sys.resume(server)
    end
  end

  test "startup, failure and stale heartbeats fail readiness, and dead owners leave no ready status" do
    parent = self()

    owner =
      spawn(fn ->
        GameReadiness.register(:starting)
        send(parent, {:started, self()})

        receive do
          :ready -> :ok
        end

        GameReadiness.publish(:ready)
        send(parent, :ready)

        receive do
          :pause -> :ok
        end

        OperationBoundary.pause(%{status: :ready, active: true})
        send(parent, :paused)

        receive do
          :stop -> :ok
        end
      end)

    on_exit(fn -> Process.exit(owner, :kill) end)
    assert_receive {:started, ^owner}, 1000
    assert GameReadiness.status(owner) == :starting

    # An owner inside init/1 cannot beat, so age never unseats :starting.
    assert GameReadiness.status(owner, System.monotonic_time(:millisecond) + 60_001) == :starting

    send(owner, :ready)
    assert_receive :ready, 1000
    assert GameReadiness.status(owner) == :ready

    assert GameReadiness.status(owner, System.monotonic_time(:millisecond) + 60_001) ==
             :unavailable

    send(owner, :pause)
    assert_receive :paused, 1000
    assert GameReadiness.status(owner) == :unavailable
    ref = Process.monitor(owner)
    send(owner, :stop)
    assert_receive {:DOWN, ^ref, :process, ^owner, :normal}, 1000
    assert GameReadiness.status(owner) == :unavailable
    assert GameReadiness.status(:missing_game_owner) == :unavailable
  end

  test "publishing without a registration reports the drop instead of reporting success" do
    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert GameReadiness.publish(:ready) == :error
      end)

    assert log =~ "owns no entry"
  end

  test "inactive owners keep publishing heartbeats" do
    server = start_supervised!({GameServer, name: nil, enabled: false})
    [{^server, {_, before}}] = Registry.lookup(GameReadiness.Registry, server)
    Process.sleep(2)
    send(server, :readiness_heartbeat)
    :sys.get_state(server)
    [{^server, {:not_configured, after_time}}] = Registry.lookup(GameReadiness.Registry, server)
    assert after_time > before
  end
end
