defmodule TijaraTides.Repo.Migrations.AddShipHandlingMetadata do
  use Ecto.Migration

  def change do
    alter table(:game_ships) do
      add(:handling_started_ms, :bigint)
      add(:handling_volume_l, :bigint)
    end

    create(
      constraint(:game_ships, :handling_started_nonnegative,
        check: "handling_started_ms IS NULL OR handling_started_ms >= 0"
      )
    )

    create(
      constraint(:game_ships, :handling_volume_nonnegative,
        check: "handling_volume_l IS NULL OR handling_volume_l >= 0"
      )
    )
  end
end
