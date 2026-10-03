defmodule TijaraTides.Repo.Migrations.CapPlayerNameStorage do
  use Ecto.Migration

  # PlayerNames caps stored names in code points; graphemes are capped separately. Company
  # names stop at 120 so generated hull names ("<company> N") fit the 140 ship cap.
  def up do
    # A NOT VALID check would still reject the next update of an over-long row inside a
    # world commit, so existing rows must already fit before the checks are added.
    execute("""
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM game_companies WHERE length(name) > 120) THEN
        RAISE EXCEPTION 'Company names exceed 120 code points; rename them before migrating';
      END IF;

      IF EXISTS (SELECT 1 FROM game_ships WHERE length(name) > 140) THEN
        RAISE EXCEPTION 'Ship names exceed 140 code points; rename them before migrating';
      END IF;
    END $$;
    """)

    execute("""
    ALTER TABLE game_markdown_presets
      DROP CONSTRAINT game_markdown_presets_name_check,
      ADD CONSTRAINT game_markdown_presets_name_check CHECK(length(name) BETWEEN 1 AND 140)
    """)

    execute(
      "ALTER TABLE game_companies ADD CONSTRAINT game_companies_name_length CHECK(length(name) BETWEEN 1 AND 120)"
    )

    execute(
      "ALTER TABLE game_ships ADD CONSTRAINT game_ships_name_length CHECK(length(name) BETWEEN 1 AND 140)"
    )
  end

  def down, do: raise("Player names longer than the previous limits must survive reload")
end
