defmodule TijaraTidesWeb.LobbyLiveTest do
  use TijaraTidesWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias TijaraTides.Infrastructure.WorldServer

  test "HTTP creates a stable guest session without attaching a connection", %{conn: conn} do
    before = WorldServer.snapshot()
    conn = get(conn, "/")
    assert html_response(conn, 200) =~ "Tijara Tides"
    id = get_session(conn, :player_id)
    assert byte_size(id) == 43
    refute html_response(conn, 200) =~ id
    second = conn |> recycle() |> get("/")
    assert get_session(second, :player_id) == id
    assert WorldServer.snapshot() == before
  end

  test "separate sessions and shared tabs observe the same live world", %{conn: conn} do
    :ok = WorldServer.subscribe("ocean")
    base = WorldServer.snapshot()
    {:ok, first, _} = live(conn, "/")
    assert_receive {:world_updated, %{revision: r1}}
    assert r1 > base.revision
    {:ok, second, _} = live(build_conn(), "/")
    assert_receive {:world_updated, snapshot}
    assert snapshot.online_players == base.online_players + 2
    assert has_element?(first, "#online-players", to_string(snapshot.online_players))
    assert has_element?(second, "#connections", to_string(snapshot.connections))
    # Older queued snapshots cannot roll the rendered state backwards.
    send(first.pid, {:world_updated, %{snapshot | revision: 0, online_players: 999}})
    refute has_element?(first, "#online-players", "999")
    stop(second)
    assert_receive {:world_updated, left}
    assert left.online_players == base.online_players + 1
    assert has_element?(first, "#online-players", to_string(left.online_players))
    stop(first)
    assert_receive {:world_updated, _}
  end

  test "two tabs with one session count as one guest", %{conn: conn} do
    :ok = WorldServer.subscribe("ocean")
    conn = get(conn, "/")
    base = WorldServer.snapshot()
    {:ok, first, _} = live(conn)
    assert_receive {:world_updated, _}
    {:ok, second, _} = conn |> recycle() |> live("/")
    assert_receive {:world_updated, snapshot}
    assert snapshot.online_players == base.online_players + 1
    assert snapshot.connections == base.connections + 2
    stop(first)
    assert_receive {:world_updated, snapshot}
    assert snapshot.online_players == base.online_players + 1
    stop(second)
    assert_receive {:world_updated, _}
  end

  test "unexpected server messages do not restart the endpoint or disconnect a guest", %{
    conn: conn
  } do
    alias TijaraTides.Infrastructure.Persistence.Readiness
    {:ok, view, _} = live(conn, "/")
    endpoint = Process.whereis(TijaraTidesWeb.Endpoint)
    owner = Process.whereis(WorldServer)
    readiness = Process.whereis(Readiness)
    snapshot = WorldServer.snapshot(owner)
    status = Readiness.status(readiness)

    send(owner, :unexpected)
    send(readiness, {nil, :unexpected})
    # Calls to the original PIDs ensure the preceding messages were processed.
    assert WorldServer.snapshot(owner) == snapshot
    assert Readiness.status(readiness) == status
    assert Process.alive?(readiness)
    assert Process.whereis(TijaraTidesWeb.Endpoint) == endpoint
    assert has_element?(view, "#connections", to_string(snapshot.connections))
    stop(view)
  end

  defp stop(view) do
    GenServer.stop(view.pid, :normal)
  end

  test "explicit attach errors render a recovery message and ignore queued world updates" do
    alias TijaraTidesWeb.LobbyLive

    # A connected socket makes mount exercise the actual WorldServer API.
    socket = %Phoenix.LiveView.Socket{
      endpoint: TijaraTidesWeb.Endpoint,
      transport_pid: self(),
      assigns: %{__changed__: %{}, flash: %{}}
    }

    for identity <- [nil, "different-guest"] do
      if identity, do: WorldServer.attach("existing-guest")
      {:ok, mounted} = LobbyLive.mount(%{}, %{"player_id" => identity}, socket)
      assert mounted.assigns.snapshot == nil
      html = render_component(&LobbyLive.render/1, mounted.assigns)
      assert html =~ "Unable to join the harbor lobby"
      assert html =~ "Reload lobby"
      refute html =~ "Connected to the shared world"
      refute html =~ ~s(id="online-players")

      assert {:noreply, ^mounted} =
               LobbyLive.handle_info({:world_updated, WorldServer.snapshot()}, mounted)
    end
  end
end
