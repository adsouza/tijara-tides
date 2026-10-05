defmodule TijaraTides.Infrastructure.Persistence.LedgerStartupTest do
  use ExUnit.Case, async: false
  @moduletag :game_database
  alias TijaraTides.SqlReplay, as: Sql
  alias TijaraTides.Infrastructure.Persistence.{Repo, GameStore, FinancialLedger}

  defmodule SnapshotRepo do
    alias TijaraTides.Infrastructure.Persistence.Repo
    def transaction(fun, opts), do: Repo.transaction(fun, opts)

    def query!(sql, params, opts \\ []) do
      result = Repo.query!(sql, params, opts)

      if String.contains?(sql, "WITH actual AS") do
        parent = Process.get(:audit_parent)
        read_only = Repo.query!("SHOW transaction_read_only").rows
        send(parent, {:history_read, self(), read_only})
        receive do: (:continue_audit -> :ok)
      end

      if String.contains?(sql, "SELECT c.id FROM game_companies c") do
        {world, company} = Process.get(:audit_company)

        cash =
          Repo.query!("SELECT cash_cents FROM game_companies WHERE world_id=$1 AND id=$2", [
            world,
            company
          ]).rows

        send(Process.get(:audit_parent), {:snapshot_cash, cash})
      end

      result
    end
  end

  setup do
    # Maintenance audits every world, so each test owns an entire disposable DB.
    port = System.fetch_env!("TIJARA_TEST_DB_PORT") |> String.to_integer()
    database = "audit_" <> String.replace(Ecto.UUID.generate(), "-", "")
    config = [hostname: "127.0.0.1", port: port, username: "postgres"]
    {:ok, admin} = Postgrex.start_link(config ++ [database: "postgres"])
    Postgrex.query!(admin, "CREATE DATABASE #{database}", [])
    GenServer.stop(admin)
    start_supervised!({Repo, config ++ [database: database, pool_size: 4]})
    Ecto.Migrator.run(Repo, TijaraTides.TestMigrations.all(), :up, all: true, log: false)

    on_exit(fn ->
      {:ok, admin} = Postgrex.start_link(config ++ [database: "postgres"])
      Postgrex.query!(admin, "DROP DATABASE #{database} WITH (FORCE)", [])
      GenServer.stop(admin)
    end)

    :ok
  end

  test "claims and reloads reconcile current state without reading journal history" do
    Sql.with_world(fn c ->
      c = Sql.company(c)
      game = :sys.get_state(c.server).game
      handler = "startup-queries-#{Ecto.UUID.generate()}"

      :telemetry.attach(
        handler,
        [:tijara_tides, :infrastructure, :persistence, :repo, :query],
        &__MODULE__.query/4,
        self()
      )

      try do
        assert {:ok, reloaded} = GameStore.reload(Repo, c.world, game)
        assert {:ok, claimed} = GameStore.claim(Repo, c.world)

        for loaded <- [reloaded, claimed] do
          assert loaded.entities["companies"] == game.entities["companies"]
          assert loaded.entities["ships"] == game.entities["ships"]
          assert loaded.clock_ms == game.clock_ms
          assert loaded.revision == game.revision
        end

        queries = drain_queries()

        refute Enum.any?(
                 queries,
                 &String.contains?(&1, ["game_journal_transactions", "game_journal_entries"])
               )

        assert Enum.count(queries, &String.contains?(&1, "SELECT c.id FROM game_companies c")) ==
                 2
      after
        :telemetry.detach(handler)
      end
    end)
  end

  test "current-state corruption blocks claims and reloads and rolls back the ownership change" do
    Sql.with_world(fn c ->
      c = Sql.company(c)
      game = :sys.get_state(c.server).game

      Repo.query!(
        "UPDATE game_companies SET cash_cents=cash_cents+1 WHERE world_id=$1 AND id=$2",
        [c.world, c.company]
      )

      for operation <- [
            fn -> GameStore.claim(Repo, c.world) end,
            fn -> GameStore.reload(Repo, c.world, game) end
          ] do
        assert_raise ArgumentError, "Company balances do not reconcile with journal", operation
      end

      assert [[game.epoch]] ==
               Repo.query!("SELECT epoch FROM game_worlds WHERE id=$1", [c.world]).rows
    end)
  end

  test "explicit audit detects historical damage while startup uses the current balances" do
    Sql.with_world(fn c ->
      c = Sql.company(c)
      game = :sys.get_state(c.server).game

      [[transaction, position]] =
        Repo.query!(
          "SELECT e.transaction_id,e.position FROM game_journal_entries e JOIN game_journal_transactions t ON t.id=e.transaction_id WHERE t.world_id=$1 ORDER BY e.transaction_id,e.position LIMIT 1",
          [c.world]
        ).rows

      # Simulate a faulty restore in this disposable DB only. Normal writes cannot
      # alter sealed entries, and the test leaves current balances untouched.
      Repo.transaction(fn ->
        Repo.query!("ALTER TABLE game_journal_entries DISABLE TRIGGER immutable_entries")

        Repo.query!(
          "UPDATE game_journal_entries SET amount_cents=amount_cents+1 WHERE transaction_id=$1 AND position=$2",
          [transaction, position]
        )

        Repo.query!("ALTER TABLE game_journal_entries ENABLE TRIGGER immutable_entries")
      end)

      assert {:ok, _} = GameStore.reload(Repo, c.world, game)
      assert {:ok, _} = GameStore.claim(Repo, c.world)
      before = world_row(c.world)

      assert_raise ArgumentError, "Ledger totals disagree with journal history", fn ->
        TijaraTides.Release.audit_ledger_repo(Repo)
      end

      assert world_row(c.world) == before
    end)
  end

  test "maintenance uses a read-only consistent snapshot while a balanced posting commits" do
    Sql.with_world(fn c ->
      c = Sql.company(c)
      parent = self()
      before = world_row(c.world)

      task =
        Task.async(fn ->
          Process.put(:audit_parent, parent)
          Process.put(:audit_company, {c.world, c.company})
          FinancialLedger.audit_all(SnapshotRepo)
        end)

      assert_receive {:history_read, pid, [["on"]]}, 5000
      assert world_row(c.world) == before

      game = :sys.get_state(c.server).game

      next =
        TijaraTides.Domain.CompanyFinanceWorld.post(game, c.company, "audit-concurrent", [
          {"cash_available", 100},
          {"sales_revenue", -100}
        ])

      Sql.persist(c, next)
      send(pid, :continue_audit)
      assert {:ok, 1} = Task.await(task)
      old_cash = game.entities["companies"][c.company]["cash"]
      assert_receive {:snapshot_cash, [[^old_cash]]}
      assert world_row(c.world) == [game.epoch, game.clock_ms, game.revision + 1]
      assert {:ok, 1} = FinancialLedger.audit_all(Repo)

      assert ExUnit.CaptureIO.capture_io(fn ->
               assert :ok = TijaraTides.Release.audit_ledger_repo(Repo)
             end) =~ "Full ledger audit passed for 1 world(s). No data changed."
    end)
  end

  def query(_event, _measurements, metadata, parent) do
    if self() == parent, do: send(parent, {:query, metadata.query})
  end

  defp drain_queries do
    receive do
      {:query, sql} -> [sql | drain_queries()]
    after
      0 -> []
    end
  end

  defp world_row(world) do
    [[epoch, clock, revision]] =
      Repo.query!("SELECT epoch,clock_ms,revision FROM game_worlds WHERE id=$1", [world]).rows

    [epoch, clock, revision]
  end
end
