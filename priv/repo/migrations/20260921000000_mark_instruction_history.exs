defmodule TijaraTides.Repo.Migrations.MarkInstructionHistory do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE game_ship_instructions ADD COLUMN history_archived boolean NOT NULL DEFAULT false"
    )

    # Legacy records have no journey identity. Retain the newest contiguous
    # destination group, plus every actionable instruction.
    execute("""
    WITH latest AS (
      SELECT DISTINCT ON (world_id, ship_id) world_id, ship_id, port_id
      FROM game_ship_instructions ORDER BY world_id, ship_id, created_ms DESC, id DESC
    )
    UPDATE game_ship_instructions o SET history_archived = true
    FROM latest l WHERE o.world_id=l.world_id AND o.ship_id=l.ship_id
      AND o.status NOT IN ('planned','waiting')
      AND (o.port_id <> l.port_id OR o.created_ms < (
        SELECT max(p.created_ms) FROM game_ship_instructions p
        WHERE p.world_id=o.world_id AND p.ship_id=o.ship_id AND p.port_id<>l.port_id
      ))
    """)
  end

  def down do
    execute("ALTER TABLE game_ship_instructions DROP COLUMN history_archived")
  end
end
