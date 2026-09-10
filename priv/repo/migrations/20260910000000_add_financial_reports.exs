defmodule TijaraTides.Repo.Migrations.AddFinancialReports do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE game_reporting_accounts (
      world_id text NOT NULL, id text NOT NULL, capital bigint NOT NULL CHECK(capital>=0),
      since_ms bigint NOT NULL, at_ms bigint NOT NULL CHECK(at_ms>=since_ms),
      PRIMARY KEY(world_id,id), FOREIGN KEY(world_id,id) REFERENCES game_companies(world_id,id)
    )
    """)

    execute("""
    CREATE TABLE game_financial_reports (
      world_id text NOT NULL, id text NOT NULL, company_id text NOT NULL,
      period text NOT NULL CHECK(period IN ('quarter','year')), period_index bigint NOT NULL CHECK(period_index>=0),
      capital_ms numeric(40,0) NOT NULL CHECK(capital_ms>=0), observed_ms bigint NOT NULL CHECK(observed_ms>=0),
      revenue bigint NOT NULL, cargo_cost bigint NOT NULL, operating bigint NOT NULL, depreciation bigint NOT NULL,
      PRIMARY KEY(world_id,id), UNIQUE(world_id,company_id,period,period_index),
      FOREIGN KEY(world_id,company_id) REFERENCES game_companies(world_id,id)
    )
    """)
  end

  def down do
    drop(table(:game_financial_reports))
    drop(table(:game_reporting_accounts))
  end
end
