defmodule TijaraTides.Infrastructure.Persistence.Repo.Migrations.Localization do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE game_accounts ADD COLUMN locale text NOT NULL DEFAULT 'en' CHECK (locale IN ('en','ar'))"
    )

    execute("ALTER TABLE game_notices ALTER COLUMN message DROP NOT NULL")

    execute(
      "ALTER TABLE game_notices ADD COLUMN code text, ADD COLUMN arguments jsonb NOT NULL DEFAULT '{}'::jsonb"
    )

    execute(
      "ALTER TABLE game_notices ADD CONSTRAINT game_notices_content CHECK ((code IS NULL AND message IS NOT NULL) OR (code IS NOT NULL AND message IS NULL))"
    )
  end

  def down do
    execute("ALTER TABLE game_notices DROP CONSTRAINT game_notices_content")

    execute(
      "UPDATE game_notices SET message=jsonb_build_object('code',code,'arguments',arguments)::text WHERE message IS NULL"
    )

    execute(
      "ALTER TABLE game_notices DROP COLUMN code, DROP COLUMN arguments, ALTER COLUMN message SET NOT NULL"
    )

    execute("ALTER TABLE game_accounts DROP COLUMN locale")
  end
end
