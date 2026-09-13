defmodule TijaraTides.Repo.Migrations.AddLuxuryAuctions do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE game_auctions (
      world_id text NOT NULL, id text NOT NULL, company_id text, warehouse_id text,
      port text NOT NULL, good text NOT NULL, quantity bigint NOT NULL CHECK(quantity BETWEEN 1 AND 10000),
      reserve bigint NOT NULL CHECK(reserve>0), opens_ms bigint NOT NULL, closes_ms bigint NOT NULL CHECK(closes_ms>opens_ms),
      status text NOT NULL CHECK(status IN ('scheduled','sold','unsold','cancelled')), price bigint, winner_id text, valuation_seed text NOT NULL,
      PRIMARY KEY(world_id,id), CHECK((company_id IS NULL)=(warehouse_id IS NULL)),
      FOREIGN KEY(world_id,company_id) REFERENCES game_companies(world_id,id),
      FOREIGN KEY(world_id,warehouse_id) REFERENCES game_warehouses(world_id,id) DEFERRABLE INITIALLY DEFERRED,
      FOREIGN KEY(world_id,winner_id) REFERENCES game_companies(world_id,id)
    )
    """)

    execute("CREATE INDEX ON game_auctions(world_id,status,closes_ms)")

    execute("""
    CREATE TABLE game_auction_bids (
      world_id text NOT NULL, id text NOT NULL, auction_id text NOT NULL, company_id text, warehouse_id text,
      amount bigint NOT NULL CHECK(amount>0), priority_ms bigint NOT NULL, priority_seq bigint NOT NULL,
      PRIMARY KEY(world_id,id), UNIQUE(world_id,auction_id,company_id),
      CHECK((company_id IS NULL)=(warehouse_id IS NULL)),
      FOREIGN KEY(world_id,auction_id) REFERENCES game_auctions(world_id,id) DEFERRABLE INITIALLY DEFERRED,
      FOREIGN KEY(world_id,company_id) REFERENCES game_companies(world_id,id),
      FOREIGN KEY(world_id,warehouse_id) REFERENCES game_warehouses(world_id,id) DEFERRABLE INITIALLY DEFERRED
    )
    """)

    # The original CHECK was unnamed; locate it by its expression, not a generated name.
    execute("""
    DO $$ DECLARE c record; BEGIN
      FOR c IN SELECT conname FROM pg_constraint WHERE conrelid='game_warehouse_reservations'::regclass
        AND contype='c' AND pg_get_constraintdef(oid) LIKE '%num_nonnulls%'
      LOOP EXECUTE format('ALTER TABLE game_warehouse_reservations DROP CONSTRAINT %I', c.conname); END LOOP;
    END $$;
    """)

    execute("""
    ALTER TABLE game_warehouse_reservations ADD COLUMN auction_id text, ADD COLUMN bid_id text,
      ADD FOREIGN KEY(world_id,auction_id) REFERENCES game_auctions(world_id,id) DEFERRABLE INITIALLY DEFERRED,
      ADD FOREIGN KEY(world_id,bid_id) REFERENCES game_auction_bids(world_id,id) DEFERRABLE INITIALLY DEFERRED,
      ADD CHECK(num_nonnulls(ship_id,order_id,auction_id,bid_id)=1)
    """)

    execute(
      "CREATE UNIQUE INDEX ON game_warehouse_reservations(world_id,auction_id) WHERE auction_id IS NOT NULL"
    )

    execute(
      "CREATE UNIQUE INDEX ON game_warehouse_reservations(world_id,bid_id) WHERE bid_id IS NOT NULL"
    )
  end

  def down, do: raise("Auction settlement history must be retained")
end
