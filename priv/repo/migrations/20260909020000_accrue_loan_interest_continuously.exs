defmodule TijaraTides.Infrastructure.Persistence.Repo.Migrations.AccrueLoanInterestContinuously do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE game_loans ADD COLUMN interest_accrued bigint NOT NULL DEFAULT 0 CHECK(interest_accrued>=0), ADD COLUMN interest_remainder bigint NOT NULL DEFAULT 0, ADD COLUMN interest_at_ms bigint NOT NULL DEFAULT 0"
    )

    # Existing periods retain their already posted interest. Start continuous
    # accrual at the migration clock rather than charging retroactively.
    execute(
      "UPDATE game_loans l SET interest_at_ms=w.clock_ms FROM game_worlds w WHERE w.id=l.world_id"
    )

    execute(
      "ALTER TABLE game_loans ADD CHECK(interest_at_ms>=created_ms), ADD CHECK(interest_remainder<=0 AND interest_remainder > -(period_ms::numeric * 10000)), ADD CHECK(status='open' OR interest_accrued=0)"
    )
  end

  def down do
    raise "Accrued loan interest is durable; restore a pre-migration database to roll back"
  end
end
