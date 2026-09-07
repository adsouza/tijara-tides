defmodule TijaraTidesWeb.Router do
  use TijaraTidesWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug TijaraTidesWeb.Plugs.GuestSession
    plug :fetch_live_flash
    plug :put_root_layout, html: {TijaraTidesWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Health probes do not create sessions or touch the world/database.
  scope "/", TijaraTidesWeb do
    get "/health", HealthController, :show
    get "/healthz", HealthController, :show
    get "/statusz", HealthController, :ready
  end

  scope "/", TijaraTidesWeb do
    pipe_through :browser

    live "/", LobbyLive
    live "/play", GameLive
    post "/session/redeem", GameSessionController, :create
    delete "/session", GameSessionController, :delete
  end

  # Other scopes may use custom stacks.
  # scope "/api", TijaraTidesWeb do
  #   pipe_through :api
  # end
end
