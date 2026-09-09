defmodule TijaraTides.Repo.Migrations.AddSponsorGuarantees do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE game_accounts ADD COLUMN suspended_ms bigint CHECK(suspended_ms>=0)")

    execute(
      "UPDATE game_accounts a SET suspended_ms=w.clock_ms FROM game_worlds w WHERE a.world_id=w.id AND (SELECT count(*) FROM game_bankruptcy_events e WHERE e.world_id=a.world_id AND e.account_id=a.id AND e.created_ms + 9676800000 > w.clock_ms)>=5"
    )

    execute("""
    CREATE TABLE game_guarantees (
      world_id text NOT NULL REFERENCES game_worlds(id), id text NOT NULL,
      company_id text NOT NULL, sponsor_id text NOT NULL, beneficiary_id text NOT NULL,
      borrower_company_id text, amount bigint NOT NULL CHECK(amount>=5000000),
      forfeited bigint NOT NULL DEFAULT 0 CHECK(forfeited>=0 AND forfeited<=amount),
      status text NOT NULL CHECK(status IN ('pledged','released','claimed')),
      created_ms bigint NOT NULL CHECK(created_ms>=0), PRIMARY KEY(world_id,id),
      CHECK(sponsor_id<>beneficiary_id), CHECK(status<>'pledged' OR forfeited=0),
      FOREIGN KEY(world_id,company_id) REFERENCES game_companies(world_id,id) DEFERRABLE INITIALLY DEFERRED,
      FOREIGN KEY(world_id,borrower_company_id) REFERENCES game_companies(world_id,id) DEFERRABLE INITIALLY DEFERRED,
      FOREIGN KEY(world_id,sponsor_id) REFERENCES game_accounts(world_id,id) DEFERRABLE INITIALLY DEFERRED,
      FOREIGN KEY(world_id,beneficiary_id) REFERENCES game_accounts(world_id,id) DEFERRABLE INITIALLY DEFERRED
    )
    """)

    execute(
      "CREATE UNIQUE INDEX game_guarantees_active ON game_guarantees(world_id,beneficiary_id) WHERE status='pledged'"
    )

    execute(
      "INSERT INTO game_ledger_accounts VALUES ('guarantee_escrow','asset'),('guarantee_expense','expense')"
    )
  end

  def down, do: raise("Sponsor guarantees cannot be rolled back after financial activity.")
end
