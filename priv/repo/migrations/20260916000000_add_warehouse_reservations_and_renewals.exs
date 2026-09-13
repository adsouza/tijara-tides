defmodule TijaraTides.Repo.Migrations.AddWarehouseReservationsAndRenewals do
  use Ecto.Migration

  def up do
    for sql <- [
          """
          ALTER TABLE game_warehouses
            ADD COLUMN renewal_rate bigint CHECK(renewal_rate>=0),
            ADD COLUMN next_rent bigint NOT NULL DEFAULT 0 CHECK(next_rent>=0),
            ADD COLUMN next_days bigint CHECK(next_days IN (1,3,7)),
            ADD COLUMN auto_days bigint CHECK(auto_days IN (1,3,7)),
            ADD COLUMN auto_cap bigint CHECK(auto_cap>=0),
            ADD CONSTRAINT warehouse_next_term CHECK((next_days IS NULL AND next_rent=0) OR next_days IS NOT NULL),
            ADD CONSTRAINT warehouse_auto_terms CHECK((auto_days IS NULL)=(auto_cap IS NULL))
          """,
          """
          CREATE TABLE game_warehouse_reservations (
            world_id text NOT NULL, id text NOT NULL, warehouse_id text NOT NULL,
            company_id text NOT NULL, ship_id text NOT NULL, good text NOT NULL,
            kind text NOT NULL CHECK(kind IN ('stock','capacity')),
            quantity bigint NOT NULL CHECK(quantity>0 AND quantity<=10000),
            created_ms bigint NOT NULL CHECK(created_ms>=0), stop_id text,
            PRIMARY KEY(world_id,id),
            FOREIGN KEY(world_id,warehouse_id) REFERENCES game_warehouses(world_id,id) DEFERRABLE INITIALLY DEFERRED,
            FOREIGN KEY(world_id,company_id) REFERENCES game_companies(world_id,id),
            FOREIGN KEY(world_id,ship_id) REFERENCES game_ships(world_id,id) DEFERRABLE INITIALLY DEFERRED
          )
          """,
          "CREATE INDEX ON game_warehouse_reservations(world_id,company_id)",
          "CREATE INDEX ON game_warehouse_reservations(world_id,warehouse_id)"
        ],
        do: execute(sql)
  end

  def down do
    raise "Renewal prepayments must be retained; restore a compatible release instead"
  end
end
