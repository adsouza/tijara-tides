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

  test "a snapshot reports what handing the reply to the caller costs", c do
    GameServer.snapshot("token", c.server)

    # Building the view is cheap because it shares structure with the owner's heap;
    # the term is flattened when it is sent. Reporting only the first number invites
    # the conclusion that reads are free.
    assert_receive {:snapshot, [:tijara_tides, :snapshot], %{duration: _, reply: reply}, _}
    assert is_integer(reply) and reply >= 0
  end

  test "the owner hands over the reply itself, so the copy falls inside the span", c do
    state = :sys.get_state(c.server)
    tag = make_ref()

    # Returning {:reply, view, state} would copy the term after the callback ends,
    # out of reach of any span inside it. This is the same send, made where it can
    # be timed, so a regression to the tuple form makes `reply` measure nothing.
    assert {:noreply, ^state} =
             GameServer.handle_call({:snapshot, "token"}, {self(), tag}, state)

    assert_receive {^tag, %{status: _}}
  end

  test "the metrics pipeline aggregates both halves of a snapshot" do
    names =
      for metric <- TijaraTidesWeb.Telemetry.metrics(),
          metric.event_name == [:tijara_tides, :snapshot],
          do: {metric.name, metric.tags}

    assert {[:tijara_tides, :snapshot, :duration], []} in names
    assert {[:tijara_tides, :snapshot, :reply], []} in names
  end
end
