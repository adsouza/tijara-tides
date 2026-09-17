defmodule TijaraTides.Repo.Migrations.ProtectMerchantHandling do
  use Ecto.Migration

  def change do
    execute(
      "ALTER TABLE game_merchant_warehouses ADD COLUMN protected_ms bigint NOT NULL DEFAULT 0",
      "ALTER TABLE game_merchant_warehouses DROP COLUMN protected_ms"
    )
  end
end
