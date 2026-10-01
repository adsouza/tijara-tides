defmodule TijaraTides.Repo.Migrations.AddWeatherDelays do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE game_ships ADD COLUMN weather jsonb CHECK(weather IS NULL OR jsonb_typeof(weather)='object')"
    )

    execute("""
    CREATE TABLE game_weather (
      world_id text NOT NULL REFERENCES game_worlds(id) ON DELETE CASCADE,
      id text NOT NULL,window_id text NOT NULL,starts_ms bigint NOT NULL,until_ms bigint NOT NULL CHECK(until_ms>starts_ms),
      PRIMARY KEY(world_id,id))
    """)
  end

  def down, do: raise("Accepted voyage progress and weather forecasts must survive reload")
end
