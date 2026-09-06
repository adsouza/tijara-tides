defmodule TijaraTides.Infrastructure.WorldServerTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Infrastructure.WorldServer

  setup do
    id = "test-#{System.unique_integer([:positive])}"
    server = start_supervised!({WorldServer, world_id: id})
    :ok = WorldServer.subscribe(id)
    %{server: server, world_id: id}
  end

  test "starts with an empty shared world and rejects unattached commands", %{server: server} do
    assert %{online_players: 0, connections: 0, revision: 0} = WorldServer.snapshot(server)
    assert {:error, :not_attached} = WorldServer.command(server, :anything)
    refute_receive {:world_updated, _}
  end

  test "attachment is idempotent; invalid identity and commands cannot mutate state", %{
    server: server
  } do
    assert {:error, :invalid_identity} = WorldServer.attach(server, nil)
    snapshot = WorldServer.attach(server, "guest")
    assert_receive {:world_updated, ^snapshot}
    assert ^snapshot = WorldServer.attach(server, "guest")
    assert {:error, :already_attached} = WorldServer.attach(server, "another-guest")

    assert {:error, :unsupported_command} =
             WorldServer.command(server, %{player_id: "another-guest", money: 100})

    assert ^snapshot = WorldServer.snapshot(server)
    refute_receive {:world_updated, _}
  end

  test "concurrent clients share one owner and tab cleanup preserves the other tab", %{
    server: server
  } do
    parent = self()
    supervisor = start_supervised!(Task.Supervisor)

    clients =
      for identity <- ["guest-a", "guest-a", "guest-b"] do
        {:ok, pid} =
          Task.Supervisor.start_child(supervisor, fn ->
            snapshot = WorldServer.attach(server, identity)
            send(parent, {:attached, self(), snapshot})

            receive do
              :disconnect -> :ok
            end
          end)

        pid
      end

    for pid <- clients, do: assert_receive({:attached, ^pid, _})
    assert %{online_players: 2, connections: 3, revision: 3} = WorldServer.snapshot(server)
    # Drain the three connection events; then wait for server-observed cleanup.
    for _ <- clients, do: assert_receive({:world_updated, _})
    [first, second, third] = clients
    send(first, :disconnect)
    assert_receive {:world_updated, %{online_players: 2, connections: 2, revision: 4}}
    send(second, :disconnect)
    assert_receive {:world_updated, %{online_players: 1, connections: 1, revision: 5}}
    send(third, :disconnect)
    assert_receive {:world_updated, %{online_players: 0, connections: 0, revision: 6}}
    assert %{revision: 6} = WorldServer.snapshot(server)
  end

  test "different worlds have isolated update topics", %{server: server} do
    other = start_supervised!({WorldServer, world_id: "other"}, id: :other_world)
    WorldServer.attach(other, "guest")
    refute_receive {:world_updated, _}
    assert %{connections: 0} = WorldServer.snapshot(server)
  end
end
