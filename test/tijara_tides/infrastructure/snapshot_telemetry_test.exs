defmodule TijaraTides.Infrastructure.SnapshotTelemetryTest do
  use ExUnit.Case, async: false
  alias TijaraTides.Infrastructure.GameServer

  setup do
    :telemetry.attach(
      "snapshot-telemetry-test",
      [:tijara_tides, :snapshot],
      fn event, measurements, metadata, pid ->
        send(pid, {:snapshot, event, measurements, metadata})
      end,
      self()
    )

    on_exit(fn -> :telemetry.detach("snapshot-telemetry-test") end)
    %{server: start_supervised!({GameServer, name: nil, enabled: false, world_id: "telemetry"})}
  end

  test "a snapshot reports its duration without allocating per-call identifiers", c do
    GameServer.snapshot("token", c.server)

    assert_receive {:snapshot, [:tijara_tides, :snapshot], %{duration: duration}, metadata}
    assert is_integer(duration) and duration >= 0

    # Snapshots run inside the world owner tens of thousands of times a second, so
    # this event carries no correlation identifier, no tags and no log line.
    assert metadata == %{}
  end

  test "the metrics pipeline aggregates snapshot duration" do
    assert Enum.any?(TijaraTidesWeb.Telemetry.metrics(), fn metric ->
             metric.event_name == [:tijara_tides, :snapshot] and
               metric.name == [:tijara_tides, :snapshot, :duration] and
               metric.tags == []
           end)
  end
end
