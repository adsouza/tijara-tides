defmodule TijaraTides.Repo.Migrations.AddCompanyParticipation do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE game_company_activity (
      world_id text NOT NULL, id text NOT NULL, company_id text NOT NULL,
      last_action_ms bigint NOT NULL CHECK(last_action_ms >= 0),
      PRIMARY KEY(world_id,id), CHECK(id=company_id),
      FOREIGN KEY(world_id,company_id) REFERENCES game_companies(world_id,id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
    )
    """)

    execute(
      "ALTER TABLE game_markets ADD COLUMN production_credit bigint NOT NULL DEFAULT 0 CHECK(production_credit BETWEEN 0 AND 9999)"
    )
  end

  def down, do: raise("Economic activity history must be retained")
end
