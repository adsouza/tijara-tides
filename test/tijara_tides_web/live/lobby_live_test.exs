defmodule TijaraTidesWeb.LobbyLiveTest do
  use TijaraTidesWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias TijaraTides.Infrastructure.WorldServer

  test "home-page tabs observe presence without counting themselves", %{conn: conn} do
    base = WorldServer.snapshot()
    {:ok, first, html} = live(conn, "/")
    {:ok, second, _} = live(build_conn(), "/")
    assert WorldServer.snapshot() == base
    assert html =~ "Players online"
    refute html =~ "Guests online"
    refute has_element?(first, "#connections")
    refute has_element?(first, "#world-id")

    snapshot = WorldServer.attach("playing-browser")
    assert has_element?(first, "#online-players", to_string(snapshot.online_players))
    assert has_element?(second, "#online-players", to_string(snapshot.online_players))
    send(first.pid, {:world_updated, %{snapshot | revision: 0, online_players: 999}})
    refute has_element?(first, "#online-players", "999")

    :ok = WorldServer.detach()
    assert has_element?(first, "#online-players", to_string(base.online_players))
    assert :ok = WorldServer.detach()
  end

  test "HTTP preserves browser identity without registering presence", %{conn: conn} do
    before = WorldServer.snapshot()
    conn = get(conn, "/")
    id = get_session(conn, :player_id)
    assert byte_size(id) == 43
    refute html_response(conn, 200) =~ id
    second = conn |> recycle() |> get("/")
    assert get_session(second, :player_id) == id
    assert WorldServer.snapshot() == before
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
    assert has_element?(view, "#online-players", to_string(snapshot.online_players))
    GenServer.stop(view.pid, :normal)
  end
end
