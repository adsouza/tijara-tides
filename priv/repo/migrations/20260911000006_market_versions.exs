defmodule TijaraTides.Infrastructure.Persistence.Repo.Migrations.MarketVersions do
  use Ecto.Migration

  def change do
    execute(
      "ALTER TABLE game_markets ADD COLUMN version bigint NOT NULL DEFAULT 0 CHECK(version >= 0)",
      "ALTER TABLE game_markets DROP COLUMN version"
    )
  end
end
