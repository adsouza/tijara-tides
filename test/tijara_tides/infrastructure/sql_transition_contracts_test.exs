defmodule TijaraTides.Infrastructure.SqlTransitionContractsTest do
  use ExUnit.Case, async: false
  @moduletag :game_database
  alias TijaraTides.SqlReplay, as: Sql
  alias TijaraTides.Domain.{AutomationWorld, State}
  alias TijaraTides.Infrastructure.Persistence.{GameStore, Repo, FinancialLedger}

  setup_all do
    Sql.repo()
  end

  test "accumulator release precedes claims across release shape ID order insertion and zero balance" do
    for release <- [:update, :delete],
        existing? <- [false, true],
        reverse_ids? <- [false, true],
        reverse_insertion? <- [false, true],
        amount <- [0, 100] do
      Sql.with_world(fn c ->
        c = Sql.company(c)
        [first, _, last] = c.ships
        {holder, claimant} = if reverse_ids?, do: {last, first}, else: {first, last}
        base = :sys.get_state(c.server).game
        ids = if existing?, do: [holder, claimant], else: [holder]
        ids = if reverse_insertion?, do: Enum.reverse(ids), else: ids
        opened = Enum.reduce(ids, base, &request(&2, c.company, &1))

        opened =
          AutomationWorld.accumulate(
            opened,
            State.get(opened, "departure_requests", holder),
            amount,
            150
          )

        before = Sql.persist(c, opened)
        assert before.entities["companies"][c.company]["reserved"] == amount

        assert [[holder, amount, 150]] ==
                 Repo.query!(
                   "SELECT ship_id,accumulated,window_deadline_ms FROM game_departure_requests WHERE world_id=$1 AND window_deadline_ms IS NOT NULL",
                   [c.world]
                 ).rows

        old = State.get(before, "departure_requests", holder)

        next =
          case release do
            :update -> AutomationWorld.release_accumulation(before, old, 350)
            :delete -> AutomationWorld.abandon_request(before, old)
          end

        next = if existing?, do: next, else: request(next, c.company, claimant)

        next =
          AutomationWorld.accumulate(
            next,
            State.get(next, "departure_requests", claimant),
            amount,
            200
          )

        after_state = Sql.persist(c, next)
        assert after_state.entities["companies"][c.company]["reserved"] == amount

        assert after_state.entities["companies"][c.company]["cash"] ==
                 base.entities["companies"][c.company]["cash"]

        assert [[claimant, amount, 200]] ==
                 Repo.query!(
                   "SELECT ship_id,accumulated,window_deadline_ms FROM game_departure_requests WHERE world_id=$1 AND window_deadline_ms IS NOT NULL",
                   [c.world]
                 ).rows

        assert Sql.reload(c).entities["departure_requests"] ==
                 after_state.entities["departure_requests"]

        if release == :delete,
          do: assert(State.get(after_state, "departure_requests", holder) == nil),
          else: assert(State.get(after_state, "departure_requests", holder)["cooldown_ms"] == 350)

        assert :ok = FinancialLedger.audit(Repo, c.world)
      end)
    end
  end

  test "an invalid second zero-balance claim rolls back every row journal revision and receipt" do
    Sql.with_world(fn c ->
      c = Sql.company(c)
      [holder, claimant, _] = c.ships
      base = :sys.get_state(c.server).game
      opened = request(base, c.company, holder) |> request(c.company, claimant)

      before =
        Sql.persist(
          c,
          AutomationWorld.accumulate(
            opened,
            State.get(opened, "departure_requests", holder),
            0,
            150
          )
        )

      invalid =
        AutomationWorld.accumulate(
          before,
          State.get(before, "departure_requests", claimant),
          0,
          200
        )
        |> TijaraTides.Domain.CompanyFinanceWorld.post(c.company, "must_rollback", [
          {"cash_available", 1},
          {"capital", -1}
        ])
        |> Map.put(:revision, before.revision + 1)

      invalid = TijaraTides.UseCases.CommitPreparation.prepare(before, invalid)
      counts = counts(c)
      durable = Sql.reload(c)

      error =
        assert_raise Postgrex.Error, fn ->
          GameStore.commit(
            Repo,
            c.world,
            before.epoch,
            before,
            invalid,
            {c.account, "invalid", "fingerprint", %{}}
          )
        end

      assert error.postgres.constraint == "game_one_departure_accumulator"
      assert Sql.reload(c).entities == durable.entities
      assert Sql.reload(c).revision == before.revision
      assert counts(c) == counts
      assert :new = GameStore.receipt(Repo, c.world, c.account, "invalid", "fingerprint")
      assert :ok = FinancialLedger.audit(Repo, c.world)
    end)
  end

  test "finance and queued trade commands retain independent effects through replay reload and restart" do
    Sql.with_world(fn c ->
      c = Sql.company(c)
      base = :sys.get_state(c.server).game
      cash = base.entities["companies"][c.company]["cash"]
      borrow = %{"action" => "borrow", "amount" => 10_000}
      reply = Sql.command(c, c.token, "borrow", borrow)
      loan = reply["loan_id"]
      borrowed = :sys.get_state(c.server).game
      assert borrowed.entities["companies"][c.company]["cash"] == cash + 10_000
      assert borrowed.entities["companies"][c.company]["profit"] == 0
      assert borrowed.entities["loans"][loan]["remaining"] == 10_000
      assert Sql.command(c, c.token, "borrow", borrow) == reply
      assert :sys.get_state(c.server).game == borrowed
      Sql.assert_rows(c, borrowed)
      c = Sql.restart(c)
      assert Sql.reload(c).entities["loans"][loan]["remaining"] == 10_000
      Sql.command(c, c.token, "repay", %{"action" => "repay", "loan" => loan})
      repaid = :sys.get_state(c.server).game
      assert repaid.entities["companies"][c.company]["cash"] == cash
      assert repaid.entities["loans"][loan]["status"] == "repaid"
      Sql.assert_rows(c, repaid)
      :sys.replace_state(c.server, &put_in(&1.catalogue["ports"]["Jakarta"]["berth_count"], 1))
      [one, two, three] = c.ships

      buy = fn ship ->
        %{
          "action" => "buy",
          "ship" => ship,
          "good" => "lumber",
          "quantity" => 1,
          "limit" => 1_000_000,
          "destination" => "Singapore"
        }
      end

      Sql.command(c, c.token, "first", buy.(one))
      committed = :sys.get_state(c.server).game.entities["ships"][one]
      assert committed["status"] == "loading"
      Sql.command(c, c.token, "second", buy.(two))
      queued = :sys.get_state(c.server).game
      queued_cash = queued.entities["companies"][c.company]["cash"]
      assert queued.entities["ships"][two]["cargo"] == []
      assert queued.entities["ships"][two]["pending_side"] == "buy"
      Sql.command(c, c.token, "cancel", %{"action" => "cancel_berth_trade", "ship" => two})
      cancelled = :sys.get_state(c.server).game
      assert cancelled.entities["companies"][c.company]["cash"] == queued_cash
      assert cancelled.entities["ships"][one] == committed
      assert cancelled.entities["ships"][two]["pending_side"] == nil
      Sql.command(c, c.token, "third", buy.(three))
      Sql.advance(c.server, 60_000)
      finished = :sys.get_state(c.server).game

      assert Enum.sum(for row <- finished.entities["ships"][three]["cargo"], do: row["quantity"]) ==
               1

      Sql.assert_rows(c, finished)
      assert :ok = FinancialLedger.audit(Repo, c.world)
    end)
  end

  test "a budget CHECK failure rolls back otherwise balanced money movement" do
    Sql.with_world(fn c ->
      c = Sql.company(c)
      base = :sys.get_state(c.server).game

      opened =
        AutomationWorld.reserve_visit(
          base,
          %{
            id: "budget",
            ship_id: hd(c.ships),
            company_id: c.company,
            stop_id: nil,
            port: "Singapore",
            configured: 100,
            visit: 0
          },
          100,
          false
        )

      before = Sql.persist(c, opened)
      durable = Sql.reload(c)
      budget = State.get(before, "visit_budgets", "budget")

      invalid =
        State.put(before, "visit_budgets", "budget", %{budget | "remaining" => 101})
        |> TijaraTides.Domain.CompanyFinanceWorld.post(c.company, "must_rollback", [
          {"cash_available", 1},
          {"capital", -1}
        ])
        |> Map.put(:revision, before.revision + 1)

      error =
        assert_raise Postgrex.Error, fn ->
          GameStore.commit(
            Repo,
            c.world,
            before.epoch,
            before,
            TijaraTides.UseCases.CommitPreparation.prepare(before, invalid)
          )
        end

      assert error.postgres.code == :check_violation
      assert Sql.reload(c).entities == durable.entities
      assert :ok = FinancialLedger.audit(Repo, c.world)
    end)
  end

  test "lot parent and conserved children span the bind-limit chunk and a late failure rolls both chunks back" do
    Sql.with_world(fn c ->
      lot = fn id, parent, quantity ->
        %{
          "id" => id,
          "parent_lot_id" => parent,
          "good" => "lumber",
          "quantity" => quantity,
          "expires_ms" => nil,
          "created_ms" => 0
        }
      end

      # 7 bound columns: 8571 rows in the first statement, one child in the next.
      rows =
        [lot.("chunk-parent", nil, 2)] ++
          Enum.map(1..8569, &lot.("chunk-root:#{&1}", nil, 1)) ++
          [lot.("chunk-a", "chunk-parent", 1), lot.("chunk-b", "chunk-parent", 1)]

      assert length(rows) == 8572

      assert {:ok, :ok} =
               Repo.transaction(fn ->
                 FinancialLedger.write_lots(Repo, c.world, %{new_lots: []}, %{new_lots: rows})
                 :ok
               end)

      assert [[8572]] ==
               Repo.query!(
                 "SELECT count(*) FROM game_cargo_lots WHERE world_id=$1 AND id LIKE 'chunk-%'",
                 [c.world]
               ).rows

      assert [[2]] ==
               Repo.query!(
                 "SELECT sum(original_quantity_lots)::bigint FROM game_cargo_lots WHERE world_id=$1 AND parent_lot_id='chunk-parent'",
                 [c.world]
               ).rows

      failed =
        Enum.map(rows, fn row ->
          %{
            row
            | "id" => "bad:" <> row["id"],
              "parent_lot_id" => if(row["parent_lot_id"], do: "bad:" <> row["parent_lot_id"])
          }
        end)
        |> List.update_at(-1, &Map.put(&1, "quantity", 0))

      error =
        assert_raise Postgrex.Error, fn ->
          Repo.transaction(fn ->
            FinancialLedger.write_lots(Repo, c.world, %{new_lots: []}, %{new_lots: failed})
          end)
        end

      assert error.postgres.code == :check_violation

      assert [[0]] ==
               Repo.query!(
                 "SELECT count(*) FROM game_cargo_lots WHERE world_id=$1 AND id LIKE 'bad:%'",
                 [c.world]
               ).rows

      assert [[8572]] ==
               Repo.query!(
                 "SELECT count(*) FROM game_cargo_lots WHERE world_id=$1 AND id LIKE 'chunk-%'",
                 [c.world]
               ).rows
    end)
  end

  defp request(game, company, ship) do
    AutomationWorld.request(
      game,
      %{
        ship_id: ship,
        company_id: company,
        port: "Singapore",
        stop_id: nil,
        visit: 0,
        configured: nil
      },
      "wait",
      900_000_000
    )
  end

  defp counts(c) do
    for table <- ~w(game_receipts game_journal_transactions game_journal_entries) do
      # Journal entries use their transaction identity rather than a world column.
      if table == "game_journal_entries" do
        Repo.query!(
          "SELECT count(*) FROM game_journal_entries e JOIN game_journal_transactions t ON t.id=e.transaction_id WHERE t.world_id=$1",
          [c.world]
        ).rows
      else
        Repo.query!("SELECT count(*) FROM #{table} WHERE world_id=$1", [c.world]).rows
      end
    end
  end
end
