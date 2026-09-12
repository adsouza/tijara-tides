defmodule TijaraTidesWeb.MetricsController do
  use TijaraTidesWeb, :controller

  def show(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("text/plain", "utf-8")
    |> send_resp(200, TijaraTidesWeb.Telemetry.scrape())
  end
end
