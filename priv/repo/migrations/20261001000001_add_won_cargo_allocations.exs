defmodule TijaraTides.Repo.Migrations.AddWonCargoAllocations do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE game_warehouse_liquidations ADD COLUMN replacement_paid bigint NOT NULL DEFAULT 0 CHECK(replacement_paid>=0)"
    )

    execute("""
    ALTER TABLE game_warehouses
      ADD COLUMN source_lease_id text,
      ADD COLUMN space_group text,
      ADD COLUMN space_volumes jsonb NOT NULL DEFAULT '{}' CHECK(jsonb_typeof(space_volumes)='object'),
      ADD COLUMN award_id text,
      ADD COLUMN award_grace boolean NOT NULL DEFAULT false,
      ADD COLUMN grace_rent bigint CHECK(grace_rent>=0),
      ADD COLUMN grace_blocks bigint CHECK(grace_blocks>0),
      ADD COLUMN grace_duration_ms bigint CHECK(grace_duration_ms>0),
      ADD CHECK(NOT award_grace OR (award_id IS NOT NULL AND space_group IS NOT NULL AND grace_blocks IS NOT NULL AND grace_duration_ms IS NOT NULL))
    """)
  end

  def down, do: raise("Won cargo allocations and paid replacements retain durable history")
end
