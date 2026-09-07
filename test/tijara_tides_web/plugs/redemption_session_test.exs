defmodule TijaraTidesWeb.Plugs.RedemptionSessionTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  alias TijaraTidesWeb.Plugs.RedemptionSession

  test "GET delivers a stable random device credential; POST never mints one" do
    get = Plug.Test.conn(:get, "/play") |> Plug.Test.init_test_session(%{})
    prepared = RedemptionSession.call(get, [])
    token = get_session(prepared, :redemption_token)
    assert {:ok, bytes} = Base.url_decode64(token, padding: false)
    assert byte_size(bytes) == 32
    assert RedemptionSession.call(prepared, []) == prepared

    post = Plug.Test.conn(:post, "/session/redeem") |> Plug.Test.init_test_session(%{})
    assert get_session(RedemptionSession.call(post, []), :redemption_token) == nil
  end

  test "existing accounts are not issued a new bootstrap credential" do
    conn =
      Plug.Test.conn(:get, "/play") |> Plug.Test.init_test_session(%{account_token: "existing"})

    assert RedemptionSession.call(conn, []) == conn
  end
end
