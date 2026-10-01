defmodule TijaraTides.Repo.Migrations.AddCompanyDormancy do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE game_company_dormancy (
      world_id text NOT NULL REFERENCES game_worlds(id), id text NOT NULL,
      company_id text NOT NULL, account_id text NOT NULL, last_visit_ms bigint NOT NULL,
      warned_ms bigint, closes_ms bigint, closed_ms bigint,
      guarantee_id text, guaranteed_debt bigint NOT NULL DEFAULT 0 CHECK(guaranteed_debt >= 0),
      PRIMARY KEY(world_id,id), CHECK(id=company_id),
      CHECK((warned_ms IS NULL AND closes_ms IS NULL) OR (warned_ms IS NOT NULL AND closes_ms > warned_ms)),
      CHECK(closed_ms IS NULL OR (closes_ms IS NOT NULL AND closed_ms >= closes_ms)),
      FOREIGN KEY(world_id,company_id) REFERENCES game_companies(world_id,id) DEFERRABLE INITIALLY DEFERRED,
      FOREIGN KEY(world_id,account_id) REFERENCES game_accounts(world_id,id) DEFERRABLE INITIALLY DEFERRED
    )
    """)

    execute("ALTER TABLE game_email_requests DROP CONSTRAINT game_email_requests_purpose_check")

    execute(
      "ALTER TABLE game_email_requests ADD CONSTRAINT game_email_requests_purpose_check CHECK(purpose IN ('login','link','invite','dormancy'))"
    )
  end

  def down, do: raise("Dormant closure history cannot be rolled back safely.")
end
