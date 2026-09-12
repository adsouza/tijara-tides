defmodule TijaraTides.Infrastructure.Persistence.Repo.Migrations.LinkGuaranteedLoans do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE game_loans ADD COLUMN guarantee_id text")
    # Only active escrows need settlement after upgrading. The old draw marker
    # identifies their borrower; include its repaid loans to preserve release eligibility.
    execute("""
    UPDATE game_loans l SET guarantee_id=g.id FROM game_guarantees g
    WHERE g.world_id=l.world_id AND g.borrower_company_id=l.company_id AND g.status='pledged'
    """)

    execute(
      "ALTER TABLE game_loans ADD CONSTRAINT loan_guarantee_fkey FOREIGN KEY(world_id,guarantee_id) REFERENCES game_guarantees(world_id,id) DEFERRABLE INITIALLY DEFERRED"
    )

    execute(
      "CREATE INDEX game_loans_guarantee ON game_loans(world_id,guarantee_id) WHERE guarantee_id IS NOT NULL"
    )
  end

  def down do
    execute("""
    UPDATE game_guarantees g SET borrower_company_id=l.company_id FROM game_loans l
    WHERE g.world_id=l.world_id AND g.id=l.guarantee_id AND g.status='pledged'
    """)

    execute("ALTER TABLE game_loans DROP COLUMN guarantee_id")
  end
end
