defmodule TijaraTides.UseCases.ReplanTest do
  use ExUnit.Case, async: true
  alias TijaraTides.UseCases.CommitExecutor

  defmodule Store do
    def reload(fun, game) when is_function(fun), do: fun.(game)
    def reload(ops, game), do: ops.reload.(game)
    def commit(ops, before, changed, receipt), do: ops.commit.(before, changed, receipt)
    def restore(_, game, _), do: game
  end

  test "retries twice, then returns the latest snapshot without halting" do
    reload = fn game -> {:ok, %{game | revision: game.revision + 1}} end

    assert {:error, :market_busy, %{revision: 3}} =
             CommitExecutor.replan(%{revision: 0, entities: %{}}, {Store, reload}, fn game ->
               send(self(), {:attempt, game.revision})
               {:halt, :market_conflict}
             end)

    for revision <- 0..2, do: assert_received({:attempt, ^revision})
    refute_received {:attempt, _}
  end

  test "reload rebuilds bounded notice visibility on rejection and retry exhaustion without writes" do
    notices =
      Map.new(1..105, fn n ->
        {"notice:#{n}", %{"account_id" => "owner", "text" => "Notice #{n}", "clock_ms" => n}}
      end)

    fresh = %{entities: %{"notices" => notices}, clock_ms: 105, revision: 0}
    reload = fn _ -> {:ok, fresh} end

    for outcome <- [:rejected, :busy] do
      calls = :atomics.new(1, [])

      result =
        CommitExecutor.replan(fresh, {Store, reload}, fn state ->
          if :atomics.add_get(calls, 1, 1) > 1 do
            assert length(state.notices_by_account["owner"]) == 100
            assert hd(state.notices_by_account["owner"])["text"] == "Notice 105"
          end

          if outcome == :rejected and :atomics.get(calls, 1) > 1,
            do: {:error, :insufficient_cash},
            else: {:halt, :market_conflict}
        end)

      assert {:error, _, loaded} = result
      assert length(loaded.notices_by_account["owner"]) == 100
      assert loaded.entities == fresh.entities
      assert Map.get(loaded, :changes, %{}) == %{}
    end
  end

  test "progression retry preserves its target time when reload observes clock advancement" do
    catalogue = TijaraTides.Infrastructure.GameCatalogue.all()

    game =
      TijaraTides.Domain.Game.initialize(
        %{clock_ms: 0, revision: 0, epoch: 1, entities: %{}},
        catalogue
      )
      |> TijaraTides.Domain.Journal.clear()

    calls = :atomics.new(1, [])

    ops = %{
      reload: fn before -> {:ok, %{before | clock_ms: 50, revision: 1}} end,
      commit: fn before, changed, _ ->
        assert changed.clock_ms == 100

        if :atomics.add_get(calls, 1, 1) == 1 do
          assert before.clock_ms == 0
          {:error, :market_conflict}
        else
          assert before.clock_ms == 50
          {:ok, :ok}
        end
      end
    }

    assert {:ok, outcome} =
             TijaraTides.UseCases.LifecycleCommands.run(
               game,
               {:advance, 100},
               %{catalogue: catalogue},
               {Store, ops}
             )

    assert outcome.game.clock_ms == 100
    assert outcome.game.revision == 2
    assert outcome.refreshed?
  end

  test "ownership loss during reload remains fatal; unrelated failures never retry" do
    reload = fn _ -> {:error, :ownership_lost} end

    assert {:halt, :ownership_lost} =
             CommitExecutor.replan(%{}, {Store, reload}, fn _ -> {:halt, :market_conflict} end)

    assert {:halt, :storage_unavailable} =
             CommitExecutor.replan(%{}, {Store, fn _ -> flunk("unexpected reload") end}, fn _ ->
               {:halt, :storage_unavailable}
             end)
  end
end
