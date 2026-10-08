defmodule TijaraTides.Repo.Migrations.AddPiracyCampaigns do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE game_piracy_campaigns (
      world_id text NOT NULL REFERENCES game_worlds(id) ON DELETE CASCADE,
      id text NOT NULL,window_id text NOT NULL,name text NOT NULL,
      announced_ms bigint NOT NULL,starts_ms bigint NOT NULL CHECK(starts_ms>=announced_ms),
      until_ms bigint NOT NULL CHECK(until_ms>starts_ms),
      PRIMARY KEY(world_id,id))
    """)
  end

  def down, do: execute("DROP TABLE game_piracy_campaigns")
end
