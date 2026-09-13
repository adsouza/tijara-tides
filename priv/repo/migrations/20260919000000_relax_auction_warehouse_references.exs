defmodule TijaraTides.Repo.Migrations.RelaxAuctionWarehouseReferences do
  use Ecto.Migration

  def up do
    # Auctions and bids are retained history: Auction.prune/1 keeps the last twenty closed
    # lots per port, which outlives the one-to-seven-day leases that backed them. Holding a
    # foreign key from that history to game_warehouses made lease clearance unable to delete
    # the row, rejecting the tick for good. Live claims keep their integrity through
    # game_warehouse_reservations, which clear_reservations/2 removes with the lease.
    # Locate the constraints by definition; their names were generated.
    for table <- ["game_auctions", "game_auction_bids"] do
      execute("""
      DO $$ DECLARE c record; BEGIN
        FOR c IN SELECT conname FROM pg_constraint
          WHERE conrelid='#{table}'::regclass AND contype='f'
            AND pg_get_constraintdef(oid) LIKE '%REFERENCES game_warehouses%'
        LOOP EXECUTE format('ALTER TABLE #{table} DROP CONSTRAINT %I', c.conname); END LOOP;
      END $$;
      """)
    end
  end

  def down, do: raise("Auction history must stay readable after its lease is cleared")
end
