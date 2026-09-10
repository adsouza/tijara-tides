defmodule TijaraTides.Repo.Migrations.OptionalRoutePurchaseCap do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE game_route_rules DROP CONSTRAINT game_route_rules_check")

    execute(
      "ALTER TABLE game_route_rules ADD CONSTRAINT game_route_rules_check CHECK (budget_cents IS NULL OR budget_cents BETWEEN 1 AND 1000000000000)"
    )
  end

  def down do
    execute("ALTER TABLE game_route_rules DROP CONSTRAINT game_route_rules_check")

    execute(
      "ALTER TABLE game_route_rules ADD CONSTRAINT game_route_rules_check CHECK (side <> 'buy' OR (budget_cents IS NOT NULL AND budget_cents BETWEEN 1 AND 1000000000000))"
    )
  end
end
