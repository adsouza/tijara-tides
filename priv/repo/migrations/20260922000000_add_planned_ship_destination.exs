defmodule TijaraTides.Repo.Migrations.AddPlannedShipDestination do
  use Ecto.Migration

  def change do
    alter table(:game_ships) do
      add(:planned_destination_port_id, :text)
    end
  end
end
