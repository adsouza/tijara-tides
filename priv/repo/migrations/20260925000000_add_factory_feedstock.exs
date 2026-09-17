defmodule TijaraTides.Repo.Migrations.AddFactoryFeedstock do
  use Ecto.Migration

  def change do
    execute(
      "ALTER TABLE game_markets ADD COLUMN feedstock boolean NOT NULL DEFAULT false",
      "ALTER TABLE game_markets DROP COLUMN feedstock"
    )
  end
end
