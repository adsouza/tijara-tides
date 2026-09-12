defmodule TijaraTides.Infrastructure.Persistence.Repo.Migrations.SequenceLotIds do
  use Ecto.Migration

  def up do
    execute("LOCK TABLE game_worlds, game_cargo_lots IN ACCESS EXCLUSIVE MODE")
    execute("CREATE SEQUENCE game_lot_id_seq AS bigint")

    execute("""
    SELECT setval('game_lot_id_seq', GREATEST(
      COALESCE((SELECT max(next_lot_id) FROM game_worlds), 1),
      COALESCE((SELECT max(substring(id FROM 5)::bigint) + 1
        FROM game_cargo_lots WHERE id ~ '^lot:[0-9]+$'), 1)
    ), false)
    """)

    execute("ALTER TABLE game_worlds DROP COLUMN next_lot_id")
  end

  def down do
    execute(
      "ALTER TABLE game_worlds ADD COLUMN next_lot_id bigint NOT NULL DEFAULT 1 CHECK(next_lot_id > 0)"
    )

    execute("UPDATE game_worlds SET next_lot_id = nextval('game_lot_id_seq')")
    execute("DROP SEQUENCE game_lot_id_seq")
  end
end
