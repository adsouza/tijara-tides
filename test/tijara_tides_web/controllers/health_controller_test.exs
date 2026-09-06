defmodule TijaraTidesWeb.HealthControllerTest do
  use TijaraTidesWeb.ConnCase, async: true

  test "health probes succeed without creating a guest session", %{conn: conn} do
    for path <- [~p"/health", ~p"/healthz"] do
      conn = get(conn, path)
      assert response(conn, 200) == "ok"
      assert get_resp_header(conn, "set-cookie") == []
      assert get_resp_header(conn, "cache-control") == ["no-store"]
      refute Map.has_key?(conn.assigns, :guest_id)
    end
  end

  test "readiness fails explicitly when no database is configured", %{conn: conn} do
    conn = get(conn, ~p"/statusz")
    assert json_response(conn, 503) == %{"database" => "not_configured"}
    assert get_resp_header(conn, "set-cookie") == []
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end
end
