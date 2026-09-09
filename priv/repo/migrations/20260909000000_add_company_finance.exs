defmodule TijaraTides.Infrastructure.Persistence.Repo.Migrations.AddCompanyFinance do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE game_companies ADD COLUMN unpaid_since bigint, ADD COLUMN arrears_since bigint, ADD COLUMN bankruptcy_ms bigint"
    )

    execute(
      "UPDATE game_companies c SET unpaid_since=w.clock_ms,arrears_since=w.clock_ms FROM game_worlds w WHERE c.world_id=w.id AND c.unpaid_cents>0"
    )

    execute("""
    CREATE TABLE game_loans (
      world_id text NOT NULL REFERENCES game_worlds(id), id text NOT NULL, company_id text NOT NULL,
      principal bigint NOT NULL CHECK(principal>0), remaining bigint NOT NULL CHECK(remaining BETWEEN 0 AND principal),
      principal_due bigint NOT NULL CHECK(principal_due BETWEEN 0 AND remaining), interest_due bigint NOT NULL CHECK(interest_due>=0),
      overdue_ms bigint, next_due_ms bigint NOT NULL, period_ms bigint NOT NULL CHECK(period_ms>0),
      periods_left integer NOT NULL CHECK(periods_left>=0), rate_bps integer NOT NULL CHECK(rate_bps>=0),
      installment bigint NOT NULL CHECK(installment>0), status text NOT NULL CHECK(status IN ('open','repaid','defaulted')),
      created_ms bigint NOT NULL, PRIMARY KEY(world_id,id),
      FOREIGN KEY(world_id,company_id) REFERENCES game_companies(world_id,id),
      CHECK(status='open' OR (remaining=0 AND principal_due=0 AND interest_due=0))
    )
    """)

    execute("""
    CREATE TABLE game_loan_installments (
      world_id text NOT NULL REFERENCES game_worlds(id), id text NOT NULL, loan_id text NOT NULL, company_id text NOT NULL,
      due_ms bigint NOT NULL, principal_due bigint NOT NULL CHECK(principal_due>=0), interest_due bigint NOT NULL CHECK(interest_due>=0),
      PRIMARY KEY(world_id,id), FOREIGN KEY(world_id,loan_id) REFERENCES game_loans(world_id,id),
      FOREIGN KEY(world_id,company_id) REFERENCES game_companies(world_id,id)
    )
    """)

    execute("CREATE INDEX ON game_loans(world_id,company_id)")
    execute("CREATE INDEX ON game_loan_installments(world_id,loan_id)")

    execute("""
    CREATE TABLE game_bankruptcy_events (
      world_id text NOT NULL REFERENCES game_worlds(id), id text NOT NULL, company_id text NOT NULL, account_id text NOT NULL,
      created_ms bigint NOT NULL, restart_ms bigint NOT NULL CHECK(restart_ms>=created_ms),
      reason text NOT NULL CHECK(reason IN ('voluntary','forced')), PRIMARY KEY(world_id,id),
      UNIQUE(world_id,company_id), FOREIGN KEY(world_id,company_id) REFERENCES game_companies(world_id,id),
      FOREIGN KEY(world_id,account_id) REFERENCES game_accounts(world_id,id)
    )
    """)

    execute("""
    CREATE TABLE game_operating_bills (
      world_id text NOT NULL REFERENCES game_worlds(id), id text NOT NULL, company_id text NOT NULL,
      due_ms bigint NOT NULL, remaining bigint NOT NULL CHECK(remaining>=0), PRIMARY KEY(world_id,id),
      FOREIGN KEY(world_id,company_id) REFERENCES game_companies(world_id,id)
    )
    """)

    execute("CREATE INDEX ON game_operating_bills(world_id,company_id)")

    execute(
      "INSERT INTO game_operating_bills SELECT world_id,id || ':' || unpaid_since,id,unpaid_since,unpaid_cents FROM game_companies WHERE unpaid_cents>0"
    )

    execute(
      "INSERT INTO game_ledger_accounts VALUES ('loan_principal','liability'),('loan_interest','liability'),('interest_expense','expense'),('receivership','equity')"
    )
  end

  def down do
    raise "Finance records are durable; restore the pre-upgrade database to roll back"
  end
end
