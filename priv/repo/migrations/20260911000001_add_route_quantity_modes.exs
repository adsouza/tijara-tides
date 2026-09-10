defmodule TijaraTides.Repo.Migrations.AddRouteQuantityModes do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE game_route_rules
      ADD COLUMN quantity_mode text NOT NULL DEFAULT 'fixed',
      ALTER COLUMN quantity_lots DROP NOT NULL,
      ADD CONSTRAINT route_quantity_mode_valid CHECK (
        (quantity_mode = 'fixed' AND quantity_lots IS NOT NULL AND quantity_lots BETWEEN 1 AND 10000)
        OR (quantity_mode = 'maximum' AND quantity_lots IS NULL));
    """)

    execute("""
    ALTER TABLE game_ship_instructions DROP CONSTRAINT game_ship_instructions_quantity_lots_check,
      ADD CONSTRAINT game_ship_instructions_quantity_lots_check CHECK (quantity_lots >= 1);
    """)
  end

  def down do
    raise "Cannot downgrade dynamic route quantities without losing player instructions"
  end
end
