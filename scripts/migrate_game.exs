# Explicit operator action: mix run --no-start scripts/migrate_game.exs
{:ok, _} = Application.ensure_all_started(:ecto_sql)
{:ok, _} = Application.ensure_all_started(:postgrex)
{:ok, _} = TijaraTides.Infrastructure.Persistence.Repo.start_link()

Ecto.Migrator.run(
  TijaraTides.Infrastructure.Persistence.Repo,
  Application.app_dir(:tijara_tides, "priv/repo/migrations"),
  :up,
  all: true
)
