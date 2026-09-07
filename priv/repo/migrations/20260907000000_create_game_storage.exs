defmodule TijaraTides.Infrastructure.Persistence.Repo.Migrations.CreateGameStorage do
  use Ecto.Migration

  def change do
    create table(:game_worlds, primary_key: false) do
      add(:id, :text, primary_key: true)
      add(:epoch, :bigint, null: false, default: 0)
      add(:clock_ms, :bigint, null: false, default: 0)
      add(:revision, :bigint, null: false, default: 0)
    end

    create table(:game_entities, primary_key: false) do
      add(:world_id, references(:game_worlds, type: :text, on_delete: :delete_all),
        primary_key: true
      )

      add(:kind, :text, primary_key: true)
      add(:id, :text, primary_key: true)
      add(:data, :map, null: false)
    end

    create table(:game_receipts, primary_key: false) do
      add(:world_id, references(:game_worlds, type: :text, on_delete: :delete_all),
        primary_key: true
      )

      add(:account_id, :text, primary_key: true)
      add(:request_id, :text, primary_key: true)
      add(:fingerprint, :text, null: false)
      add(:result, :map, null: false)
    end
  end
end
