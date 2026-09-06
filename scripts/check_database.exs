# Read-only connection verification. Does not boot the world, migrate, or write.
# Run with DATABASE_URL exported: mix run --no-start scripts/check_database.exs
{:ok, _} = Application.ensure_all_started(:ecto_sql)
{:ok, _} = Application.ensure_all_started(:ssl)

alias TijaraTides.Infrastructure.Persistence.{DatabaseConfig, Repo}

url = System.get_env("DATABASE_URL") || raise "Set DATABASE_URL before checking the database"
options = DatabaseConfig.options(url) |> Keyword.put(:pool_size, 1)
Application.put_env(:tijara_tides, Repo, options)
{:ok, repo} = Repo.start_link()

try do
  case Ecto.Adapters.SQL.query(Repo, "SELECT 1", [], log: false) do
    {:ok, %{rows: [[1]]}} ->
      IO.puts("Database connection verified over certificate-verified TLS. No data changed.")

    {:error, _} ->
      raise "Database connection check failed; no data changed"
  end
after
  Supervisor.stop(repo)
end
