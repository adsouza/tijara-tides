defmodule TijaraTidesWeb.HealthController do
  use TijaraTidesWeb, :controller

  def show(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> text("ok")
  end

  def ready(conn, _params) do
    status = TijaraTides.UseCases.Game.database_readiness()

    game = if status == :ready, do: TijaraTides.UseCases.Game.readiness()
    body = if status == :ready, do: %{database: status, game: game}, else: %{database: status}

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(if status == :ready and game == :ready, do: 200, else: 503)
    |> json(body)
  end
end
