defmodule TijaraTides.Repo.Migrations.AddWarehouses do
  use Ecto.Migration

  def up do
    sql = """
    CREATE TABLE game_warehouses (
      world_id text NOT NULL, id text NOT NULL, company_id text NOT NULL,
      port text NOT NULL, storage text NOT NULL CHECK(storage IN ('dry','reefer','liquid')),
      good text, blocks bigint NOT NULL CHECK(blocks>0),
      started_ms bigint NOT NULL CHECK(started_ms>=0), expires_ms bigint NOT NULL CHECK(expires_ms>=started_ms),
      rent bigint NOT NULL CHECK(rent>=0), prepaid bigint NOT NULL CHECK(prepaid>=0 AND prepaid<=rent),
      protected_ms bigint NOT NULL CHECK(protected_ms>=0),
      PRIMARY KEY(world_id,id),
      FOREIGN KEY(world_id,company_id) REFERENCES game_companies(world_id,id),
      CHECK((storage='liquid')=(good IS NOT NULL))
    );
    CREATE INDEX ON game_warehouses(world_id,company_id);
    ALTER TABLE game_cargo_holdings ADD COLUMN warehouse_id text,
      ADD FOREIGN KEY(world_id,warehouse_id) REFERENCES game_warehouses(world_id,id) DEFERRABLE INITIALLY DEFERRED,
      ADD UNIQUE(world_id,warehouse_id,position) DEFERRABLE INITIALLY DEFERRED,
      DROP CONSTRAINT game_cargo_holdings_check,
      DROP CONSTRAINT game_cargo_holdings_check1,
      ADD CONSTRAINT cargo_single_location CHECK(num_nonnulls(ship_id,market_id,warehouse_id)=1),
      ADD CONSTRAINT cargo_owned_cost CHECK((market_id IS NULL)=(unit_cost_cents IS NOT NULL));
    CREATE VIEW game_warehouse_cargo_batches AS
      SELECT h.world_id,h.warehouse_id,h.position,h.quantity_lots,l.expires_ms,l.good_id,h.unit_cost_cents,h.lot_id
      FROM game_cargo_holdings h JOIN game_cargo_lots l ON l.world_id=h.world_id AND l.id=h.lot_id
      WHERE h.warehouse_id IS NOT NULL;
    INSERT INTO game_ledger_accounts VALUES ('prepaid_rent','asset'),('rent_expense','expense');
    """

    for statement <- String.split(sql, ";", trim: true),
        String.trim(statement) != "",
        do: execute(statement)
  end

  def down do
    raise "Warehouse cargo and journal history must be retained; restore a compatible release instead"
  end
end
