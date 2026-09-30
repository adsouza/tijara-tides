defmodule TijaraTides.Repo.Migrations.AddInvitationProgress do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE game_invitation_progress (
      world_id text NOT NULL, id text NOT NULL, account_id text NOT NULL,
      company_id text,
      checked_ms bigint NOT NULL CHECK(checked_ms >= 0),
      active_until_ms bigint NOT NULL CHECK(active_until_ms >= 0),
      progress_ms bigint NOT NULL CHECK(progress_ms >= 0 AND progress_ms < 172800000),
      PRIMARY KEY(world_id,id), CHECK(id=account_id),
      FOREIGN KEY(world_id,account_id) REFERENCES game_accounts(world_id,id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
      FOREIGN KEY(world_id,company_id) REFERENCES game_companies(world_id,id) DEFERRABLE INITIALLY DEFERRED
    )
    """)
  end

  def down, do: raise("Earned invitation progress must be retained")
end
