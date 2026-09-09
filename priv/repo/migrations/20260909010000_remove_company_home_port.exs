defmodule TijaraTides.Infrastructure.Persistence.Repo.Migrations.RemoveCompanyHomePort do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE game_companies DROP COLUMN home_port_id")
  end

  def down do
    raise "Historical home ports are no longer retained; restore a pre-migration database to roll back"
  end
end
