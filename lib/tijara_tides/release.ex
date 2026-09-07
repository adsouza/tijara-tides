defmodule TijaraTides.Release do
  @moduledoc "Explicit database maintenance and standalone launch invitation seeding."
  use Boundary,
    top_level?: true,
    deps: [TijaraTides.Infrastructure, Ecto, Ecto.Repo, Ecto.Adapters.SQL, Ecto.Migrator]

  alias TijaraTides.Infrastructure.Persistence.Repo

  def migrate do
    with_repo("Migration", fn repo ->
      Ecto.Migrator.run(repo, Application.app_dir(:tijara_tides, "priv/repo/migrations"), :up,
        all: true
      )
    end)
  end

  def check_database do
    with_repo("Connectivity check", fn repo ->
      %{rows: [[1]]} = Ecto.Adapters.SQL.query!(repo, "SELECT 1", [], log: false)
      IO.puts("Database connection verified. No data changed.")
      :ok
    end)
  end

  @doc "Create a launch invitation with the normal server stopped. Call via eval or mix run --no-start."
  def seed do
    prepare_target("Launch invitation")
    {:ok, _} = Application.ensure_all_started(:tijara_tides)

    case TijaraTides.Infrastructure.GameServer.seed() do
      {:ok, code} -> IO.puts("Launch-root invitation (single use): #{code}")
      {:error, reason} -> raise "Game is unavailable: #{reason}"
    end
  end

  @doc false
  def prepare_target(operation) do
    Application.load(:tijara_tides)

    if System.get_env("DATABASE_URL") && System.get_env("TIJARA_LOCAL_DB_PORT") do
      raise "Both DATABASE_URL and TIJARA_LOCAL_DB_PORT are set; unset the unintended target"
    end

    unless Application.get_env(:tijara_tides, :start_repo, false),
      do: raise("Game storage is not configured")

    config = Repo.config()
    IO.puts("#{operation} target: #{target(config)}")
    :ok
  end

  defp with_repo(operation, fun) do
    prepare_target(operation)
    {:ok, result, _} = Ecto.Migrator.with_repo(Repo, fun)
    result
  end

  @doc false
  def target(config) do
    # Repo.config resolves URL fields. Never print the URL, username or password.
    host = Keyword.fetch!(config, :hostname)
    database = Keyword.fetch!(config, :database)
    "#{host}:#{Keyword.get(config, :port, 5432)}/#{database}"
  end
end
