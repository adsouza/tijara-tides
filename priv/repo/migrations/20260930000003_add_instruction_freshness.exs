defmodule TijaraTides.Infrastructure.Persistence.Repo.Migrations.AddInstructionFreshness do
  use Ecto.Migration

  def change do
    for table <- ["game_ship_instructions", "game_route_rules"] do
      execute(
        "ALTER TABLE #{table} ADD COLUMN min_remaining_ms bigint NOT NULL DEFAULT 0 CHECK(min_remaining_ms BETWEEN 0 AND 2592000000 AND (side='buy' OR min_remaining_ms=0))",
        "ALTER TABLE #{table} DROP COLUMN min_remaining_ms"
      )
    end
  end
end
