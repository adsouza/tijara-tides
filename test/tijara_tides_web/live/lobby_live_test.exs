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

  defp stop(view) do
    GenServer.stop(view.pid, :normal)
  end
end
