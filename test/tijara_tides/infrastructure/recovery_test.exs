defmodule TijaraTides.Infrastructure.RecoveryTest do
  use ExUnit.Case, async: false
  alias TijaraTides.Infrastructure.WorldServer

  test "losing the owner restarts the endpoint and leaves a fresh usable world" do
    owner = Process.whereis(WorldServer)
    endpoint = Process.whereis(TijaraTidesWeb.Endpoint)
    endpoint_ref = Process.monitor(endpoint)
    pubsub = Process.whereis(TijaraTides.PubSub)

    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^endpoint_ref, :process, ^endpoint, :shutdown}, 5_000

    # This synchronous call waits until the supervisor finishes restarting children.
    children = Supervisor.which_children(TijaraTides.Supervisor)
    assert {WorldServer, new_owner, :worker, _} = List.keyfind(children, WorldServer, 0)
    assert new_owner != owner
    assert Process.whereis(TijaraTidesWeb.Endpoint) != endpoint
    assert Process.whereis(TijaraTides.PubSub) == pubsub
    assert %{connections: 0, revision: 0} = WorldServer.snapshot()
  end
end
