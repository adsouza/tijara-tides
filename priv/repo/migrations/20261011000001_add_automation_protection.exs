defmodule TijaraTides.Infrastructure.Persistence.Repo.Migrations.AddAutomationProtection do
  use Ecto.Migration

  def up do
    for table <- ~w(game_ship_routes game_departure_requests) do
      execute(
        "ALTER TABLE #{table} ADD COLUMN protection text NOT NULL DEFAULT 'none' CHECK (protection IN ('none','guards','insurance','both'))"
      )
    end
  end

  def down do
    for table <- ~w(game_departure_requests game_ship_routes),
        do: execute("ALTER TABLE #{table} DROP COLUMN protection")
  end
end
