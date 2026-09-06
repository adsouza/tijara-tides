defmodule TijaraTidesWeb.HealthController do
  use TijaraTidesWeb, :controller

  def show(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> text("ok")
  end

  def ready(conn, _params) do
    status = TijaraTides.Infrastructure.Persistence.Readiness.status()

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(if status == :ready, do: 200, else: 503)
    |> json(%{database: status})
  end
end
