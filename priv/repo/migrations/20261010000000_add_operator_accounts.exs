defmodule TijaraTides.Repo.Migrations.AddOperatorAccounts do
  use Ecto.Migration

  def change do
    alter table(:game_accounts) do
      add(:operator, :boolean, null: false, default: false)
    end
  end
end
