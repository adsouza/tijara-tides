defmodule TijaraTides.Repo.Migrations.EnableRouteAutoDeparture do
  use Ecto.Migration

  def up do
    execute("UPDATE game_ship_routes SET auto_depart=true")
    execute("ALTER TABLE game_ship_routes ALTER COLUMN auto_depart SET DEFAULT true")
  end

  def down do
    # Do not revoke automatic departure on players' running routes.
    execute("ALTER TABLE game_ship_routes ALTER COLUMN auto_depart DROP DEFAULT")
  end
end
