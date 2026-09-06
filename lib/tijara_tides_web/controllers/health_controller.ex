defmodule TijaraTidesWeb.HealthController do
  use TijaraTidesWeb, :controller

  def show(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> text("ok")
  end
end
