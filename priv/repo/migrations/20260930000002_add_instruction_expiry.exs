defmodule TijaraTides.Infrastructure.Persistence.Repo.Migrations.AddInstructionExpiry do
  use Ecto.Migration

  def change do
    execute(
      "ALTER TABLE game_ship_instructions ADD COLUMN expires_ms bigint CHECK(expires_ms > created_ms)",
      "ALTER TABLE game_ship_instructions DROP COLUMN expires_ms"
    )
  end
end
