defmodule TijaraTides.Infrastructure.RelationalStorageTest do
  use ExUnit.Case, async: false
  @moduletag :game_database
  alias TijaraTides.Domain.Game
  alias TijaraTides.Infrastructure.GameCatalogue
  alias TijaraTides.Infrastructure.Persistence.GameStore

  defmodule MigrationRepo do
    use Ecto.Repo, otp_app: :tijara_tides, adapter: Ecto.Adapters.Postgres
  end

  setup do
    port = System.fetch_env!("TIJARA_TEST_DB_PORT") |> String.to_integer()
    schema = "migration_" <> String.replace(Ecto.UUID.generate(), "-", "")
    # Isolate both the old and new schemas from the gameplay integration tests.
    {:ok, admin} =
      Postgrex.start_link(
        hostname: "127.0.0.1",
        port: port,
        username: "postgres",
        database: "postgres"
      )

    Postgrex.query!(admin, "CREATE SCHEMA #{schema}", [])

    start_supervised!(
      {MigrationRepo,
       hostname: "127.0.0.1",
       port: port,
       username: "postgres",
       database: "postgres",
       pool_size: 2,
       parameters: [search_path: schema]}
    )

    on_exit(fn ->
      {:ok, cleanup} =
        Postgrex.start_link(
          hostname: "127.0.0.1",
          port: port,
          username: "postgres",
          database: "postgres"
        )

      Postgrex.query!(cleanup, "DROP SCHEMA #{schema} CASCADE", [])
      GenServer.stop(cleanup)
    end)

    GenServer.stop(admin)
    migrations = Application.app_dir(:tijara_tides, "priv/repo/migrations")
    Ecto.Migrator.run(MigrationRepo, migrations, :up, to: 20_260_907_000_000, log: false)
    %{migrations: migrations}
  end

  defp legacy_state do
    catalogue = GameCatalogue.all()
    state = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 2, revision: 10}, catalogue)
    {:ok, state, _} = Game.seed_invite(state, "seed-hash")

    {:ok, state, _} =
      Game.redeem(state, "seed-hash", "session-hash", %{id: "account", wall_ms: 0})

    {:ok, state, _} =
      Game.execute(
        state,
        Game.get(state, "accounts", "account"),
        %{
          "action" => "company",
          "name" => "Migration company",
          "port" => "Jakarta",
          "package" => "general"
        },
        %{id: "company", catalogue: catalogue},
        catalogue
      )

    state =
      Game.put(state, "notices", "notice", %{
        "account_id" => "account",
        "text" => "Preserve this notice",
        "clock_ms" => 0
      })

    ship = Game.get(state, "ships", "company:1")

    cargo = [
      %{"good" => "Lumber", "quantity" => 2, "unit_cost" => 22500, "expires_ms" => nil},
      %{"good" => "Lumber", "quantity" => 3, "unit_cost" => 24000, "expires_ms" => nil}
    ]

    Game.put(state, "ships", ship["id"], %{ship | "cargo" => cargo})
  end

  defp store_legacy(state) do
    MigrationRepo.query!(
      "INSERT INTO game_worlds(id,epoch,clock_ms,revision) VALUES ('ocean',$1,$2,$3)",
      [state.epoch, state.clock_ms, state.revision]
    )

    for {kind, entities} <- state.entities, {id, data} <- entities do
      data = legacy_data(kind, data)

      MigrationRepo.query!(
        "INSERT INTO game_entities(world_id,kind,id,data) VALUES ('ocean',$1,$2,$3)",
        [kind, id, data]
      )
    end
  end

  defp legacy_data("ships", data),
    do:
      data
      |> Map.delete("book_value")
      |> Map.update!("cargo", &Enum.map(&1, fn row -> Map.delete(row, "lot_id") end))

  defp legacy_data("markets", data),
    do: Map.update!(data, "batches", &Enum.map(&1, fn row -> Map.delete(row, "lot_id") end))

  defp legacy_data(_, data), do: data

  defp legacy_entities(entities),
    do:
      Map.new(entities, fn {kind, rows} ->
        {kind, Map.new(rows, fn {id, data} -> {id, legacy_data(kind, data)} end)}
      end)

  test "migration preserves all domain data, batches, and receipts; typed constraints reject invalid edits",
       %{migrations: migrations} do
    original = legacy_state()
    store_legacy(original)

    MigrationRepo.query!(
      "INSERT INTO game_receipts VALUES ('ocean','bootstrap','request','fingerprint',$1)",
      [%{"account_id" => "account"}]
    )

    Ecto.Migrator.run(MigrationRepo, migrations, :up, all: true, log: false)
    {:ok, loaded} = GameStore.claim(MigrationRepo)
    assert legacy_entities(loaded.entities) == legacy_entities(original.entities)
    assert loaded.clock_ms == original.clock_ms
    assert loaded.revision == original.revision

    assert {:replay, %{"account_id" => "account"}} ==
             GameStore.receipt(MigrationRepo, "ocean", "bootstrap", "request", "fingerprint")

    assert [[nil]] == MigrationRepo.query!("SELECT to_regclass('game_entities')").rows

    assert [[2]] ==
             MigrationRepo.query!(
               "SELECT count(*) FROM game_ship_cargo_batches WHERE ship_id='company:1'"
             ).rows

    assert_raise Postgrex.Error, fn ->
      MigrationRepo.query!("UPDATE game_ships SET company_id='missing' WHERE id='company:1'")
    end

    assert_raise Postgrex.Error, fn ->
      MigrationRepo.query!("UPDATE game_companies SET cash_cents=-1 WHERE id='company'")
    end

    assert_raise Postgrex.Error, fn ->
      MigrationRepo.query!(
        "UPDATE game_ship_cargo_batches SET quantity_lots=0 WHERE ship_id='company:1'"
      )
    end

    # A scalar ship update must not rewrite any unchanged cargo batch.
    before_batches =
      MigrationRepo.query!(
        "SELECT position,xmin::text FROM game_cargo_holdings WHERE ship_id='company:1' ORDER BY position"
      ).rows

    changed = put_in(loaded, [:entities, "ships", "company:1", "name"], "Renamed")
    assert {:ok, :ok} = GameStore.commit(MigrationRepo, "ocean", loaded.epoch, loaded, changed)

    assert MigrationRepo.query!(
             "SELECT position,xmin::text FROM game_cargo_holdings WHERE ship_id='company:1' ORDER BY position"
           ).rows == before_batches

    # FIFO position can change without replacing permanent lot identities.
    [first, second] = changed.entities["ships"]["company:1"]["cargo"]
    next = put_in(changed, [:entities, "ships", "company:1", "cargo"], [second, first])
    assert {:ok, :ok} = GameStore.commit(MigrationRepo, "ocean", loaded.epoch, changed, next)
    {:ok, restored} = GameStore.claim(MigrationRepo)
    assert restored.entities == next.entities

    # Direct maintenance edits use ordinary typed columns and survive reload.
    MigrationRepo.query!(
      "UPDATE game_ships SET name='Operator name' WHERE world_id='ocean' AND id='company:1'"
    )

    {:ok, edited} = GameStore.claim(MigrationRepo)
    assert edited.entities["ships"]["company:1"]["name"] == "Operator name"
  end

  test "unknown legacy fields abort the migration without dropping original data", %{
    migrations: migrations
  } do
    original =
      legacy_state() |> put_in([:entities, "ships", "company:1", "unexpected_field"], true)

    store_legacy(original)

    assert_raise Postgrex.Error, fn ->
      Ecto.Migrator.run(MigrationRepo, migrations, :up, all: true, log: false)
    end

    assert [[true]] ==
             MigrationRepo.query!(
               "SELECT (data->>'unexpected_field')::boolean FROM game_entities WHERE kind='ships' AND id='company:1'"
             ).rows

    assert [[nil]] == MigrationRepo.query!("SELECT to_regclass('game_ships')").rows
  end
end
