defmodule TijaraTides.Repo.Migrations.AddWarehouseDisplayNumbers do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE game_warehouses ADD COLUMN display_number bigint NOT NULL DEFAULT 1 CHECK(display_number > 0)"
    )

    execute("""
    WITH numbered AS (
      SELECT world_id, id,
             row_number() OVER (PARTITION BY world_id, company_id ORDER BY started_ms, id) AS n
      FROM game_warehouses
    )
    UPDATE game_warehouses w SET display_number = n.n
    FROM numbered n WHERE w.world_id = n.world_id AND w.id = n.id
    """)
  end

  def down do
    execute("ALTER TABLE game_warehouses DROP COLUMN display_number")
  end
end
