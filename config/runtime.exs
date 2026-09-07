import Config

# No connection during ordinary tests, even if the shell has Neon credentials.
if config_env() != :test do
  local_port = if config_env() == :dev, do: System.get_env("TIJARA_LOCAL_DB_PORT")

  cond do
    local_port ->
      config :tijara_tides, :start_repo, true

      config :tijara_tides, TijaraTides.Infrastructure.Persistence.Repo,
        hostname: "127.0.0.1",
        port: String.to_integer(local_port),
        username: "postgres",
        database: "tijara_tides",
        ssl: false,
        pool_size: 2,
        idle_limit: 0

    database_url = System.get_env("DATABASE_URL") ->
      config :tijara_tides, :start_repo, true

      config :tijara_tides,
             TijaraTides.Infrastructure.Persistence.Repo,
             TijaraTides.Infrastructure.Persistence.DatabaseConfig.options(database_url)

    true ->
      :ok
  end
end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/tijara_tides start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :tijara_tides, TijaraTidesWeb.Endpoint, server: true
end

config :tijara_tides, TijaraTidesWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :tijara_tides, TijaraTidesWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/tijara_tides_web/router\.ex$"E,
        ~r"lib/tijara_tides_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  config :tijara_tides, :game_secret, secret_key_base

  host = System.get_env("PHX_HOST") || System.get_env("RENDER_EXTERNAL_HOSTNAME") || "example.com"

  config :tijara_tides, TijaraTidesWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0}],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :tijara_tides, TijaraTidesWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :tijara_tides, TijaraTidesWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
