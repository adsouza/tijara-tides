defmodule TijaraTides.Repo.Migrations.AddVoyageDiversions do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE game_ships ADD COLUMN paid_canals integer CHECK(paid_canals BETWEEN 0 AND 3)"
    )

    execute("""
    CREATE TABLE game_ship_voyage_points (
      world_id text NOT NULL, ship_id text NOT NULL, position integer NOT NULL CHECK(position>=0),
      longitude double precision NOT NULL CHECK(longitude>=-180 AND longitude<=180),
      latitude double precision NOT NULL CHECK(latitude>=-90 AND latitude<=90),
      PRIMARY KEY(world_id,ship_id,position),
      FOREIGN KEY(world_id,ship_id) REFERENCES game_ships(world_id,id) ON DELETE CASCADE
    )
    """)
  end

  def down do
    raise "Active diverted voyages require their stored geometry; use a compatible release"
  end
end
