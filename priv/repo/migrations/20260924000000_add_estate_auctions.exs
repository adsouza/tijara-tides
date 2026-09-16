defmodule TijaraTides.Repo.Migrations.AddEstateAuctions do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE game_ships ADD COLUMN acquired_ms bigint, ADD COLUMN acquisition_value bigint CHECK(acquisition_value > 0)"
    )

    execute("ALTER TABLE game_auctions ADD COLUMN ship_id text")

    execute("""
    DO $$ DECLARE c record; BEGIN
      FOR c IN SELECT conname, conrelid::regclass AS tbl FROM pg_constraint
        WHERE conrelid IN ('game_auctions'::regclass,'game_auction_bids'::regclass)
        AND contype='c' AND pg_get_constraintdef(oid) LIKE '%company_id%'
      LOOP EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', c.tbl, c.conname); END LOOP;
    END $$;
    """)

    execute(
      "ALTER TABLE game_auctions ADD CHECK ((ship_id IS NOT NULL AND company_id IS NOT NULL AND warehouse_id IS NULL AND quantity=1) OR (ship_id IS NULL AND (company_id IS NULL)=(warehouse_id IS NULL)))"
    )

    execute(
      "ALTER TABLE game_auction_bids ADD CHECK(company_id IS NOT NULL OR warehouse_id IS NULL)"
    )

    execute(
      "CREATE UNIQUE INDEX ON game_auctions(world_id,ship_id) WHERE ship_id IS NOT NULL AND status='scheduled'"
    )
  end

  def down, do: raise("Estate settlement history must be retained")
end
