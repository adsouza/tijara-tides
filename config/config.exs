# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :tijara_tides,
  start_repo: false,
  ecto_repos: [TijaraTides.Infrastructure.Persistence.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :tijara_tides, TijaraTidesWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: TijaraTidesWeb.ErrorHTML, json: TijaraTidesWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TijaraTides.PubSub,
  live_view: [signing_salt: "n/1ekTLI"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  tijara_tides: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  tijara_tides: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Local-only default; production replaces this with SECRET_KEY_BASE.
config :tijara_tides,
       :game_secret,
       "tijara-local-invitation-secret-not-for-production-01234567890123456789"

config :phoenix, :filter_parameters, ["password", "secret", "token", "code", "email"]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
config :swoosh, :api_client, false
config :tijara_tides, :email_enabled, false
config :tijara_tides, TijaraTides.Infrastructure.Mailer, adapter: Swoosh.Adapters.Local

import_config "#{config_env()}.exs"
