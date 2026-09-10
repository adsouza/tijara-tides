defmodule TijaraTides.Repo.Migrations.SnapshotInstructionQuantityMode do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE game_ship_instructions ADD COLUMN quantity_mode text NOT NULL DEFAULT 'fixed' CHECK (quantity_mode IN ('fixed','maximum'))"
    )

    execute(
      "UPDATE game_ship_instructions i SET quantity_mode = r.quantity_mode FROM game_route_rules r WHERE i.world_id=r.world_id AND i.id='route:' || r.id"
    )
  end

  def down do
    execute("ALTER TABLE game_ship_instructions DROP COLUMN quantity_mode")
  end
end
