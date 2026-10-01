defmodule TijaraTides.Repo.Migrations.AddGradedBooks do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE game_ship_instructions ADD COLUMN markdowns jsonb, ADD COLUMN price_floor bigint CHECK(price_floor >= 0)"
    )

    execute("""
    ALTER TABLE game_exchange_orders
      ADD COLUMN min_grade bigint NOT NULL DEFAULT 0 CHECK(min_grade BETWEEN 0 AND 3),
      ADD COLUMN min_remaining_ms bigint NOT NULL DEFAULT 0 CHECK(min_remaining_ms BETWEEN 0 AND 2592000000),
      ADD COLUMN initial_price bigint CHECK(initial_price>0),
      ADD COLUMN markdowns jsonb CHECK(markdowns IS NULL OR jsonb_typeof(markdowns)='object'),
      ADD COLUMN price_floor bigint NOT NULL DEFAULT 0 CHECK(price_floor>=0),
      ADD COLUMN portions jsonb NOT NULL DEFAULT '{}' CHECK(jsonb_typeof(portions)='object')
    """)

    execute("""
    CREATE TABLE game_markdown_presets (
      world_id text NOT NULL REFERENCES game_worlds(id) ON DELETE CASCADE,
      id text NOT NULL,account_id text NOT NULL,name text NOT NULL CHECK(length(name) BETWEEN 1 AND 80),
      markdowns jsonb NOT NULL CHECK(jsonb_typeof(markdowns)='object'),price_floor bigint NOT NULL CHECK(price_floor>=0),
      PRIMARY KEY(world_id,id),FOREIGN KEY(world_id,account_id) REFERENCES game_accounts(world_id,id))
    """)

    execute(
      "CREATE INDEX game_markdown_presets_owner ON game_markdown_presets(world_id,account_id)"
    )
  end

  def down, do: raise("Accepted graded order terms and priority must survive reload")
end
