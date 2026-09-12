defmodule TijaraTides.Infrastructure.Persistence.Repo.Migrations.RecordGuaranteedDebt do
  use Ecto.Migration

  def change do
    execute(
      "ALTER TABLE game_bankruptcy_events ADD COLUMN guaranteed_debt_cents bigint NOT NULL DEFAULT 0 CHECK(guaranteed_debt_cents >= 0)",
      "ALTER TABLE game_bankruptcy_events DROP COLUMN guaranteed_debt_cents"
    )

    # Names the escrow this closure consumed, so the sponsor settles exactly that
    # guarantee rather than inferring one from timestamps.
    execute(
      "ALTER TABLE game_bankruptcy_events ADD COLUMN guarantee_id text",
      "ALTER TABLE game_bankruptcy_events DROP COLUMN guarantee_id"
    )
  end
end
