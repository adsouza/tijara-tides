defmodule TijaraTides.Repo.Migrations.UniqueShipNames do
  use Ecto.Migration

  def up do
    execute("""
    DO $$
    DECLARE duplicate record; candidate text; suffix bigint;
    BEGIN
      FOR duplicate IN
        SELECT world_id, id, name FROM (
          SELECT world_id, id, name,
                 row_number() OVER (PARTITION BY world_id, name ORDER BY built_ms, id) AS position
          FROM game_ships
        ) ranked WHERE position > 1 ORDER BY world_id, name, id
      LOOP
        suffix := 2;
        LOOP
          candidate := duplicate.name || ' (' || suffix || ')';
          EXIT WHEN NOT EXISTS (
            SELECT 1 FROM game_ships WHERE world_id=duplicate.world_id AND name=candidate
          );
          suffix := suffix + 1;
        END LOOP;
        UPDATE game_ships SET name=candidate WHERE world_id=duplicate.world_id AND id=duplicate.id;
      END LOOP;
    END $$;
    """)

    create(unique_index(:game_ships, [:world_id, :name]))
  end

  def down do
    drop(unique_index(:game_ships, [:world_id, :name]))
  end
end
