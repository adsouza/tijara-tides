defmodule TijaraTides.Repo.Migrations.AddMerchantWarehouses do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE game_merchant_warehouses (
      world_id text NOT NULL, id text NOT NULL, port text NOT NULL, good text NOT NULL,
      storage text NOT NULL CHECK(storage IN ('dry','reefer','liquid')),
      blocks bigint NOT NULL CHECK(blocks>0), capacity bigint NOT NULL CHECK(capacity>0),
      expires_ms bigint NOT NULL CHECK(expires_ms>=0), PRIMARY KEY(world_id,id),
      FOREIGN KEY(world_id,id) REFERENCES game_markets(world_id,id) DEFERRABLE INITIALLY DEFERRED
    )
    """)
  end

  def down, do: raise("Merchant inventory and paid leases must be retained")
end
