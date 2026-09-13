defmodule TijaraTides.Repo.Migrations.AddBerthQueue do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE game_ships
    ADD COLUMN berth_queued_ms bigint CHECK(berth_queued_ms >= 0),
    ADD COLUMN berth_granted_ms bigint CHECK(berth_granted_ms >= 0),
    ADD COLUMN berth_retry_ms bigint CHECK(berth_retry_ms >= 0),
    ADD COLUMN pending_side text CHECK(pending_side IN ('buy','sell')),
    ADD COLUMN pending_good text,
    ADD COLUMN pending_quantity bigint CHECK(pending_quantity > 0 AND pending_quantity <= 10000),
    ADD COLUMN pending_limit bigint CHECK(pending_limit >= 0),
    ADD COLUMN pending_destination text,
    ADD CONSTRAINT pending_berth_trade_complete CHECK (
      (pending_side IS NULL AND pending_good IS NULL AND pending_quantity IS NULL AND pending_limit IS NULL AND pending_destination IS NULL)
      OR (pending_side IS NOT NULL AND pending_good IS NOT NULL AND pending_quantity IS NOT NULL AND pending_limit IS NOT NULL)),
    ADD CONSTRAINT berth_single_state CHECK(berth_queued_ms IS NULL OR berth_granted_ms IS NULL)
    """)
  end

  def down do
    execute(
      "ALTER TABLE game_ships DROP COLUMN berth_queued_ms, DROP COLUMN berth_granted_ms, DROP COLUMN berth_retry_ms, DROP COLUMN pending_side, DROP COLUMN pending_good, DROP COLUMN pending_quantity, DROP COLUMN pending_limit, DROP COLUMN pending_destination"
    )
  end
end
