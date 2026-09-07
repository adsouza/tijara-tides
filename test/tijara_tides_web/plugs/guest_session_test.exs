defmodule TijaraTidesWeb.Plugs.GuestSessionTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  alias TijaraTidesWeb.Plugs.GuestSession

  test "missing and malformed identities are replaced with a random 32-byte identity" do
    sessions = [
      %{} | Enum.map([nil, "", "short", String.duplicate("a", 44), 123, %{}], &%{player_id: &1})
    ]

    ids =
      for session <- sessions do
        conn = Plug.Test.conn(:get, "/") |> Plug.Test.init_test_session(session)
        id = conn |> GuestSession.call([]) |> get_session(:player_id)
        assert byte_size(id) == 43
        assert {:ok, bytes} = Base.url_decode64(id, padding: false)
        assert byte_size(bytes) == 32
        id
      end

    assert length(Enum.uniq(ids)) == length(ids)
  end

  test "a valid existing identity and unrelated session data are preserved" do
    id = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    conn =
      Plug.Test.conn(:get, "/")
      |> Plug.Test.init_test_session(%{player_id: id, other: "retained"})

    assert GuestSession.call(conn, GuestSession.init([])) == conn
    assert get_session(conn, :player_id) == id
    assert get_session(conn, :other) == "retained"
  end
end
