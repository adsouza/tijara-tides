defmodule TijaraTides.Infrastructure.Persistence.Repo.Migrations.AddQueueTradeMargins do
  use Ecto.Migration

  # Null means the player is asked for a margin each time a trade must queue.
  def up do
    for column <- ~w(queue_margin_buy_bps queue_margin_sell_bps) do
      execute(
        "ALTER TABLE game_accounts ADD COLUMN #{column} integer CHECK (#{column} BETWEEN 0 AND 1000)"
      )
    end
  end

  def down do
    execute(
      "ALTER TABLE game_accounts DROP COLUMN queue_margin_sell_bps, DROP COLUMN queue_margin_buy_bps"
    )
  end
end
