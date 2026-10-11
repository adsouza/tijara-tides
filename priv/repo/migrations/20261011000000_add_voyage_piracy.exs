defmodule TijaraTides.Repo.Migrations.AddVoyagePiracy do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE game_ships ADD COLUMN piracy jsonb")

    execute(
      "INSERT INTO game_ledger_accounts(code,category) VALUES ('piracy_guard_expense','expense'),('piracy_premium_expense','expense'),('piracy_charge_expense','expense')"
    )
  end

  def down do
    execute("ALTER TABLE game_ships DROP COLUMN piracy")

    execute(
      "DELETE FROM game_ledger_accounts WHERE code IN ('piracy_guard_expense','piracy_premium_expense','piracy_charge_expense')"
    )
  end
end
