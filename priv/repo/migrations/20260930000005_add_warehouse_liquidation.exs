defmodule TijaraTides.Repo.Migrations.AddWarehouseLiquidation do
  use Ecto.Migration

  def up do
    sql = """
    ALTER TABLE game_warehouses
      ADD COLUMN grace_ms bigint NOT NULL DEFAULT 43200000 CHECK(grace_ms>0),
      ADD COLUMN surcharge_bps bigint NOT NULL DEFAULT 2500 CHECK(surcharge_bps>=0),
      ADD COLUMN window_ms bigint NOT NULL DEFAULT 7200000 CHECK(window_ms>0),
      ADD COLUMN clearance_bps bigint NOT NULL DEFAULT 1000 CHECK(clearance_bps BETWEEN 0 AND 10000),
      DROP CONSTRAINT game_warehouses_blocks_check,
      ADD CONSTRAINT game_warehouses_blocks_check CHECK(blocks>=0);
    CREATE TABLE game_warehouse_liquidations (
      world_id text NOT NULL REFERENCES game_worlds(id), id text NOT NULL,
      company_id text NOT NULL, port text NOT NULL,
      status text NOT NULL CHECK(status IN ('grace','liquidating','completed')),
      expires_ms bigint NOT NULL, grace_end_ms bigint NOT NULL CHECK(grace_end_ms>expires_ms),
      last_ms bigint NOT NULL CHECK(last_ms>=expires_ms),
      original_blocks bigint NOT NULL CHECK(original_blocks>0),
      occupied_blocks bigint NOT NULL CHECK(occupied_blocks>=0 AND occupied_blocks<=original_blocks),
      rent bigint NOT NULL CHECK(rent>=0), duration_ms bigint NOT NULL CHECK(duration_ms>0),
      surcharge_bps bigint NOT NULL CHECK(surcharge_bps>=0), window_ms bigint NOT NULL CHECK(window_ms>0),
      clearance_bps bigint NOT NULL CHECK(clearance_bps BETWEEN 0 AND 10000),
      handling_rate bigint NOT NULL CHECK(handling_rate>=0),
      rent_due bigint NOT NULL CHECK(rent_due>=0), rent_remainder bigint NOT NULL CHECK(rent_remainder>=0),
      handling_due bigint NOT NULL CHECK(handling_due>=0),
      clearance_remainders jsonb NOT NULL DEFAULT '{}' CHECK(jsonb_typeof(clearance_remainders)='object'),
      proceeds bigint NOT NULL CHECK(proceeds>=0),
      charged bigint NOT NULL CHECK(charged>=0), paid bigint NOT NULL CHECK(paid>=0),
      sunk bigint NOT NULL CHECK(sunk>=0), completed_ms bigint,
      PRIMARY KEY(world_id,id),
      FOREIGN KEY(world_id,company_id) REFERENCES game_companies(world_id,id) DEFERRABLE INITIALLY DEFERRED,
      CHECK(charged+paid+sunk<=proceeds),
      CHECK((status='completed')=(completed_ms IS NOT NULL)),
      CHECK(status<>'completed' OR charged+paid+sunk=proceeds)
    );
    CREATE INDEX ON game_warehouse_liquidations(world_id,company_id);
    ALTER TABLE game_auctions ADD COLUMN liquidation_id text, ADD COLUMN expires_ms bigint,
      ADD FOREIGN KEY(world_id,liquidation_id) REFERENCES game_warehouse_liquidations(world_id,id) DEFERRABLE INITIALLY DEFERRED,
      ADD CHECK(liquidation_id IS NULL OR (warehouse_id=liquidation_id AND company_id IS NOT NULL AND ship_id IS NULL));
    """

    for statement <- String.split(sql, ";", trim: true), do: execute(statement)
  end

  def down,
    do: raise("Liquidation accounting and completed payouts cannot be rolled back safely.")
end
