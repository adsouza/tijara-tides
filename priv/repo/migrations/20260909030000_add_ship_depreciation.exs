defmodule TijaraTides.Repo.Migrations.AddShipDepreciation do
  use Ecto.Migration

  def up do
    execute(
      "CREATE TABLE game_ship_identities (world_id text NOT NULL REFERENCES game_worlds(id) ON DELETE CASCADE, id text NOT NULL, PRIMARY KEY(world_id,id))"
    )

    execute("INSERT INTO game_ship_identities SELECT world_id,id FROM game_ships")

    execute(
      "CREATE FUNCTION remember_ship_identity() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN INSERT INTO game_ship_identities(world_id,id) VALUES(NEW.world_id,NEW.id) ON CONFLICT DO NOTHING; RETURN NEW; END $$"
    )

    execute(
      "CREATE TRIGGER remember_ship_identity BEFORE INSERT ON game_ships FOR EACH ROW EXECUTE FUNCTION remember_ship_identity()"
    )

    execute(
      "ALTER TABLE game_journal_transactions DROP CONSTRAINT game_journal_transactions_world_id_ship_id_fkey, ADD FOREIGN KEY(world_id,ship_id) REFERENCES game_ship_identities(world_id,id) DEFERRABLE INITIALLY DEFERRED"
    )

    execute(
      "ALTER TABLE game_ships ADD COLUMN built_ms bigint, ADD COLUMN build_value_cents bigint"
    )

    execute(
      "UPDATE game_ships s SET built_ms=w.clock_ms, build_value_cents=s.book_value_cents FROM game_worlds w WHERE w.id=s.world_id"
    )

    execute(
      "ALTER TABLE game_ships ALTER COLUMN built_ms SET NOT NULL, ALTER COLUMN build_value_cents SET NOT NULL, ADD CHECK(built_ms>=0), ADD CHECK(build_value_cents>=0)"
    )

    execute(
      "INSERT INTO game_ledger_accounts VALUES ('depreciation_expense','expense'),('ship_disposal_expense','expense')"
    )
  end

  def down do
    raise "Ship depreciation cannot be rolled back after financial activity."
  end
end
