defmodule TijaraTides.Infrastructure.Persistence.Repo.Migrations.AllowContinuousVoyageLongitudes do
  use Ecto.Migration

  # Departures store the catalogue route as sailed. Routes keep longitude
  # continuous across the antimeridian (Busan to Los Angeles reaches 241.9), and
  # weather zones read those raw values, so the path cannot be wrapped on write.
  # A path that starts within one turn of the globe stays within one more.
  def up do
    execute("""
    ALTER TABLE game_ship_voyage_points
      DROP CONSTRAINT game_ship_voyage_points_longitude_check,
      ADD CONSTRAINT game_ship_voyage_points_longitude_check
        CHECK(longitude>=-540 AND longitude<=540)
    """)
  end

  def down do
    execute("""
    ALTER TABLE game_ship_voyage_points
      DROP CONSTRAINT game_ship_voyage_points_longitude_check,
      ADD CONSTRAINT game_ship_voyage_points_longitude_check
        CHECK(longitude>=-180 AND longitude<=180)
    """)
  end
end
