defmodule TijaraTides.Repo.Migrations.AddOrderBooks do
  use Ecto.Migration

  def up do
    for sql <- [
          """
          CREATE TABLE game_exchange_orders (
            world_id text NOT NULL, id text NOT NULL, company_id text NOT NULL, warehouse_id text NOT NULL,
            port text NOT NULL, good text NOT NULL, side text NOT NULL CHECK(side IN ('buy','sell')),
            quantity bigint NOT NULL CHECK(quantity BETWEEN 1 AND 10000), price bigint NOT NULL CHECK(price BETWEEN 1 AND 1000000000000),
            priority_ms bigint NOT NULL, priority_seq bigint NOT NULL, expires_ms bigint,
            PRIMARY KEY(world_id,id),
            FOREIGN KEY(world_id,company_id) REFERENCES game_companies(world_id,id),
            FOREIGN KEY(world_id,warehouse_id) REFERENCES game_warehouses(world_id,id) DEFERRABLE INITIALLY DEFERRED
          )
          """,
          "CREATE INDEX ON game_exchange_orders(world_id,port,good,side,price,priority_ms,priority_seq)",
          "CREATE INDEX ON game_exchange_orders(world_id,company_id)",
          "ALTER TABLE game_warehouse_reservations ALTER COLUMN ship_id DROP NOT NULL, ADD COLUMN order_id text, ADD FOREIGN KEY(world_id,order_id) REFERENCES game_exchange_orders(world_id,id) DEFERRABLE INITIALLY DEFERRED, ADD CHECK(num_nonnulls(ship_id,order_id)=1)",
          "CREATE UNIQUE INDEX ON game_warehouse_reservations(world_id,order_id) WHERE order_id IS NOT NULL",
          """
          CREATE TABLE game_exchange_trades (
            world_id text NOT NULL, id text NOT NULL, port text NOT NULL, good text NOT NULL,
            quantity bigint NOT NULL CHECK(quantity>0), price bigint NOT NULL CHECK(price>0),
            clock_ms bigint NOT NULL, sequence bigint NOT NULL, PRIMARY KEY(world_id,id)
          )
          """
        ],
        do: execute(sql)
  end

  def down, do: raise("Exchange settlements and ledger history must be retained")
end
