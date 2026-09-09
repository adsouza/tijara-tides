defmodule TijaraTides.Infrastructure.RelationalStorageTest do
  use ExUnit.Case, async: false
  @moduletag :game_database
  alias TijaraTides.Domain.Game
  alias TijaraTides.Infrastructure.GameCatalogue
  alias TijaraTides.Infrastructure.Persistence.GameStore

  defmodule MigrationRepo do
    use Ecto.Repo, otp_app: :tijara_tides, adapter: Ecto.Adapters.Postgres
  end

  defmodule FailingStartupMigration do
    use Ecto.Migration
    def up, do: raise("deliberate migration failure")
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
       pool_size: 4,
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
    migrations = TijaraTides.TestMigrations.all()
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
      TijaraTides.CompanyFixture.execute(
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
      TijaraTides.Domain.State.put(state, "notices", "notice", %{
        "account_id" => "account",
        "text" => "Preserve this notice",
        "clock_ms" => 0
      })

    ship = Game.get(state, "ships", "company:1")

    cargo = [
      %{"good" => "lumber", "quantity" => 2, "unit_cost" => 22500, "expires_ms" => nil},
      %{"good" => "lumber", "quantity" => 3, "unit_cost" => 24000, "expires_ms" => nil}
    ]

    TijaraTides.Domain.State.put(state, "ships", ship["id"], %{ship | "cargo" => cargo})
  end

  # Build pre-migration fixtures from modern domain data without changing expected state.
  defp legacy_ids(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {legacy_ids(key), legacy_ids(item)} end)

  defp legacy_ids(value) when is_list(value), do: Enum.map(value, &legacy_ids/1)

  defp legacy_ids(value) when is_binary(value) do
    ids = %{
      "agricultural_machinery" => "Agricultural machinery",
      "appliances" => "Appliances",
      "construction_equipment" => "Construction equipment",
      "copper_scrap" => "Copper scrap",
      "crude_oil" => "Crude oil",
      "designer_clothing" => "Designer clothing",
      "electronics" => "Electronics",
      "everyday_clothing" => "Everyday clothing",
      "fruit" => "Fruit",
      "grain" => "Grain",
      "iron_ore" => "Iron ore",
      "jewelry" => "Jewelry",
      "lumber" => "Lumber",
      "meat" => "Meat",
      "recovered_plastics" => "Recovered plastics",
      "refined_fuel" => "Refined fuel",
      "aluminium_scrap" => "Scrap aluminium",
      "seafood" => "Seafood",
      "spices" => "Spices",
      "turbines" => "Turbines",
      "vegetable_oil" => "Vegetable oil",
      "whisky" => "Whisky"
    }

    value |> String.split("|") |> Enum.map(&Map.get(ids, &1, &1)) |> Enum.join("|")
  end

  defp legacy_ids(value), do: value

  defp store_legacy(state) do
    MigrationRepo.query!(
      "INSERT INTO game_worlds(id,epoch,clock_ms,revision) VALUES ('ocean',$1,$2,$3)",
      [state.epoch, state.clock_ms, state.revision]
    )

    for {kind, entities} <- legacy_ids(state.entities), {id, data} <- entities do
      data = legacy_data(kind, data)

      MigrationRepo.query!(
        "INSERT INTO game_entities(world_id,kind,id,data) VALUES ('ocean',$1,$2,$3)",
        [kind, id, data]
      )
    end
  end

  defp legacy_data("accounts", data), do: Map.drop(data, ["suspended_ms", "email"])

  defp legacy_data("companies", data),
    do:
      data
      |> Map.drop(["unpaid_since", "arrears_since", "bankruptcy_ms"])
      |> Map.put("home", "Jakarta")

  defp legacy_data("ships", data),
    do:
      data
      |> Map.drop(["book_value", "built_ms", "build_value"])
      |> Map.update!("cargo", &Enum.map(&1, fn row -> Map.delete(row, "lot_id") end))

  defp legacy_data("markets", data),
    do: Map.update!(data, "batches", &Enum.map(&1, fn row -> Map.delete(row, "lot_id") end))

  defp legacy_data(_, data), do: data

  defp legacy_entities(entities),
    do:
      Map.new(entities, fn {kind, rows} ->
        {kind, Map.new(rows, fn {id, data} -> {id, legacy_data(kind, data)} end)}
      end)

  test "startup migration fences writers, is idempotent and rejects older releases", %{
    migrations: migrations
  } do
    state = legacy_state()
    store_legacy(state)
    assert [_ | _] = TijaraTides.Release.migrate_repo(MigrationRepo, migrations)
    assert [[epoch]] = MigrationRepo.query!("SELECT epoch FROM game_worlds WHERE id='ocean'").rows
    assert epoch == state.epoch + 1
    assert [] == TijaraTides.Release.migrate_repo(MigrationRepo, migrations)

    assert [[^epoch]] =
             MigrationRepo.query!("SELECT epoch FROM game_worlds WHERE id='ocean'").rows

    assert {:error, :ownership_lost} =
             GameStore.commit(MigrationRepo, "ocean", state.epoch, state, state)

    assert_raise RuntimeError, ~r/absent from this release/, fn ->
      TijaraTides.Release.migrate_repo(MigrationRepo, Enum.drop(migrations, -1))
    end

    # Both successful and rejected migrations release the advisory lock.
    assert {:ok, loaded} = GameStore.claim(MigrationRepo)
    assert loaded.epoch == epoch + 1

    assert_raise RuntimeError, "deliberate migration failure", fn ->
      TijaraTides.Release.migrate_repo(
        MigrationRepo,
        migrations ++ [{20_269_999_000_000, FailingStartupMigration}]
      )
    end

    assert {:error, :ownership_lost} =
             GameStore.commit(MigrationRepo, "ocean", loaded.epoch, loaded, loaded)

    assert [] == TijaraTides.Release.migrate_repo(MigrationRepo, migrations)
    assert {:ok, _} = GameStore.claim(MigrationRepo)
  end

  test "world claims wait for the migration lock", %{migrations: migrations} do
    TijaraTides.Release.migrate_repo(MigrationRepo, migrations)
    parent = self()

    holder =
      Task.async(fn ->
        TijaraTides.Infrastructure.Persistence.SchemaMaintenance.with_lock(MigrationRepo, fn ->
          send(parent, :migration_locked)
          receive do: (:release_migration -> :ok)
        end)
      end)

    assert_receive :migration_locked
    claimant = Task.async(fn -> GameStore.claim(MigrationRepo) end)
    assert Task.yield(claimant, 100) == nil
    send(holder.pid, :release_migration)
    assert :ok = Task.await(holder)
    assert {:ok, _} = Task.await(claimant)
  end

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
    refute Map.has_key?(loaded.entities["companies"]["company"], "home")

    assert [[0]] =
             MigrationRepo.query!(
               "SELECT count(*) FROM information_schema.columns WHERE table_schema=current_schema() AND table_name='game_companies' AND column_name='home_port_id'"
             ).rows

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

  test "first instruction migration creates independent visit plans without cargo orders", %{
    migrations: migrations
  } do
    store_legacy(legacy_state())
    Ecto.Migrator.run(MigrationRepo, migrations, :up, to: 20_260_908_000_000, log: false)

    MigrationRepo.query!("""
    INSERT INTO game_visit_plans(world_id,id,ship_id,company_id,port_id,onward_port_id)
    VALUES('ocean','company:1|Singapore','company:1','company','Singapore','Jakarta')
    """)

    assert [[0]] == MigrationRepo.query!("SELECT count(*) FROM game_ship_instructions").rows

    assert [["company:1", "Singapore", "Jakarta"]] ==
             MigrationRepo.query!("SELECT ship_id,port_id,onward_port_id FROM game_visit_plans").rows

    assert_raise Postgrex.Error, fn ->
      MigrationRepo.query!("""
      INSERT INTO game_visit_plans(world_id,id,ship_id,company_id,port_id,onward_port_id)
      VALUES('ocean','duplicate','company:1','company','Singapore','Dubai')
      """)
    end

    assert_raise Postgrex.Error, fn ->
      MigrationRepo.query!("UPDATE game_visit_plans SET onward_port_id=port_id")
    end

    Ecto.Migrator.run(MigrationRepo, migrations, :down, to: 20_260_908_000_000, log: false)

    assert [[nil, nil]] ==
             MigrationRepo.query!(
               "SELECT to_regclass('game_ship_instructions'),to_regclass('game_visit_plans')"
             ).rows

    assert [[3]] == MigrationRepo.query!("SELECT count(*) FROM game_ships").rows
    Ecto.Migrator.run(MigrationRepo, migrations, :up, all: true, log: false)
    {:ok, loaded} = GameStore.claim(MigrationRepo)
    assert Game.entities(loaded, "visit_plans") == %{}
    assert Game.entities(loaded, "ship_instructions") == %{}
  end

  test "machine cargo IDs preserve holdings, lineage, journal postings and receipts", %{
    migrations: migrations
  } do
    store_legacy(legacy_state())
    Ecto.Migrator.run(MigrationRepo, migrations, :up, to: 20_260_908_000_000, log: false)

    MigrationRepo.query!(
      "UPDATE game_ships SET last_liquid_good_id='Vegetable oil' WHERE id='company:2'"
    )

    MigrationRepo.query!("""
    INSERT INTO game_ship_instructions(world_id,id,company_id,ship_id,port_id,good_id,side,quantity_lots,filled_lots,limit_cents,budget_cents,spent_cents,onward_port_id,status,reason,created_ms)
    VALUES('ocean','order','company','company:1','Singapore','Scrap aluminium','buy',5,2,100000,1000000,200000,'Jakarta','waiting','Waiting for handling',0)
    """)

    MigrationRepo.query!(
      "INSERT INTO game_receipts VALUES ('ocean','account','trade','unchanged-fingerprint',$1)",
      [%{"quantity" => 2, "spent" => 200_000}]
    )

    MigrationRepo.query!("""
    SELECT post_game_journal('ocean','company','handling',0,10,'trade','company:1','Scrap aluminium',ARRAY['cash_available','handling_expense'],ARRAY[-1000,1000]::bigint[])
    """)

    MigrationRepo.query!(
      "UPDATE game_companies SET cash_cents=cash_cents-1000,profit_cents=profit_cents-1000 WHERE id='company'"
    )

    # Include immutable split lineage, not just unsplit legacy stock.
    MigrationRepo.transaction(fn ->
      MigrationRepo.query!(
        "INSERT INTO game_cargo_lots(world_id,id,good_id,original_quantity_lots,created_ms) VALUES ('ocean','parent','Scrap aluminium',5,0)"
      )

      MigrationRepo.query!(
        "INSERT INTO game_cargo_lots(world_id,id,parent_lot_id,good_id,original_quantity_lots,created_ms) VALUES ('ocean','child-a','parent','Scrap aluminium',2,0),('ocean','child-b','parent','Scrap aluminium',3,0)"
      )
    end)

    tables =
      ~w(game_cargo_types game_worlds game_companies game_ships game_markets game_cargo_lots game_cargo_holdings game_ship_instructions game_journal_transactions game_journal_entries game_ledger_balances game_receipts)

    snapshot = fn ->
      Map.new(tables, fn table ->
        rows =
          MigrationRepo.query!("SELECT to_jsonb(t) FROM #{table} t ORDER BY to_jsonb(t)::text").rows

        {table, rows}
      end)
    end

    before = snapshot.()

    Ecto.Migrator.run(MigrationRepo, migrations, :up, to: 20_260_908_020_000, log: false)
    after_migration = snapshot.()

    for table <-
          ~w(game_worlds game_companies game_journal_entries game_ledger_balances game_receipts) do
      assert after_migration[table] == before[table]
    end

    assert [["aluminium_scrap", 3]] ==
             MigrationRepo.query!(
               "SELECT good_id,count(*) FROM game_cargo_lots WHERE id IN ('parent','child-a','child-b') GROUP BY good_id"
             ).rows

    assert [["vegetable_oil"]] ==
             MigrationRepo.query!(
               "SELECT last_liquid_good_id FROM game_ships WHERE id='company:2'"
             ).rows

    assert [["aluminium_scrap", 5, 2, 200_000]] ==
             MigrationRepo.query!(
               "SELECT good_id,quantity_lots,filled_lots,spent_cents FROM game_ship_instructions WHERE id='order'"
             ).rows

    assert [["aluminium_scrap", true]] ==
             MigrationRepo.query!(
               "SELECT good_id,sealed FROM game_journal_transactions WHERE request_id='trade'"
             ).rows

    assert [[0]] ==
             MigrationRepo.query!(
               "SELECT count(*) FROM game_markets WHERE id<>port_id || '|' || good_id"
             ).rows

    assert [[0]] ==
             MigrationRepo.query!(
               "SELECT count(*) FROM game_cargo_holdings h JOIN game_markets m ON h.world_id=m.world_id AND h.market_id=m.id JOIN game_cargo_lots l ON h.world_id=l.world_id AND h.lot_id=l.id WHERE m.good_id<>l.good_id"
             ).rows

    assert [[22]] ==
             MigrationRepo.query!(
               "SELECT count(*) FROM game_cargo_types WHERE id ~ '^[a-z]+(_[a-z]+)*$'"
             ).rows

    assert {:replay, %{"quantity" => 2, "spent" => 200_000}} ==
             GameStore.receipt(
               MigrationRepo,
               "ocean",
               "account",
               "trade",
               "unchanged-fingerprint"
             )

    assert_raise Postgrex.Error, fn ->
      MigrationRepo.query!("UPDATE game_cargo_lots SET good_id='lumber' WHERE id='parent'")
    end

    assert_raise Postgrex.Error, fn ->
      MigrationRepo.query!(
        "UPDATE game_journal_transactions SET good_id='lumber' WHERE request_id='trade'"
      )
    end

    # Prove the reverse cargo migration restores every row.
    Ecto.Migrator.run(MigrationRepo, migrations, :down, to: 20_260_908_020_000, log: false)
    assert snapshot.() == before
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
