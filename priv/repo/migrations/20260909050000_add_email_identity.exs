defmodule TijaraTides.Repo.Migrations.AddEmailIdentity do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE game_accounts ADD COLUMN email text CHECK(email=lower(email))")

    execute(
      "CREATE UNIQUE INDEX game_accounts_email ON game_accounts(world_id,email) WHERE email IS NOT NULL"
    )

    execute("""
    CREATE TABLE game_email_requests (
      world_id text NOT NULL REFERENCES game_worlds(id), id text NOT NULL,
      token_hash text NOT NULL, email text NOT NULL, purpose text NOT NULL CHECK(purpose IN ('login','link','invite')),
      account_id text, requester text NOT NULL, created_ms bigint NOT NULL, expires_ms bigint NOT NULL,
      attempts integer NOT NULL DEFAULT 0, retry_ms bigint NOT NULL DEFAULT 0,
      used_session text, delivery text NOT NULL CHECK(delivery IN ('pending','sent','ignored','failed')),
      PRIMARY KEY(world_id,id), UNIQUE(world_id,token_hash),
      FOREIGN KEY(world_id,account_id) REFERENCES game_accounts(world_id,id) DEFERRABLE INITIALLY DEFERRED
    )
    """)
  end

  def down, do: raise("Verified identities cannot be rolled back safely.")
end
