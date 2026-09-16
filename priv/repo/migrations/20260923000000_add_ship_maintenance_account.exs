defmodule TijaraTides.Repo.Migrations.AddShipMaintenanceAccount do
  use Ecto.Migration

  def up do
    execute(
      "INSERT INTO game_ledger_accounts(code,category) VALUES ('maintenance_expense','expense')"
    )
  end

  def down do
    execute("DELETE FROM game_ledger_accounts WHERE code='maintenance_expense'")
  end
end
