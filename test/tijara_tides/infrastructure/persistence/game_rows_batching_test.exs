defmodule TijaraTides.Infrastructure.Persistence.GameRowsBatchingTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.State
  alias TijaraTides.Infrastructure.Persistence.GameRows

  # A world tick changes every moving ship at once. Writing a statement per row costs
  # one database round trip per row, which dominates the tick; these tests pin the
  # batching so a regression to row-at-a-time is caught without a load run.
  defmodule CountingRepo do
    def query!(sql, params) do
      send(self(), {:sql, sql, params})

      # Cargo lot identity is read back before a holding is written, and the market version
      # check counts the rows it claimed. Answer for whichever rows the statement names, so
      # these tests measure round trips and not missing data.
      cond do
        String.contains?(sql, "game_cargo_lots") ->
          %{rows: Enum.map(lots(List.last(params)), &[&1, "rice", 999]), num_rows: 1}

        String.contains?(sql, "game_markets") and String.contains?(sql, "version") ->
          %{rows: [], num_rows: length(lots(Enum.at(params, 1)))}

        true ->
          %{rows: [], num_rows: 1}
      end
    end

    defp lots(ids) when is_list(ids), do: ids
    defp lots(id), do: [id]
  end

  defp ship(id, burned) do
    %{
      "id" => id,
      "company_id" => "company",
      "name" => id,
      "class" => "freighter",
      "status" => "docked",
      "port" => "Jakarta",
      "cargo" => [],
      "fuel_burned" => burned
    }
  end

  defp statements do
    receive do
      {:sql, sql, params} -> [{sql, params} | statements()]
    after
      0 -> []
    end
  end

  defp sql, do: Enum.map(statements(), &elem(&1, 0))

  defp world(count, burned) do
    %{entities: %{"ships" => Map.new(1..count, &{"s#{&1}", ship("s#{&1}", burned)})}}
  end

  test "updating many rows of one kind issues one statement" do
    before = world(50, 0)

    changed =
      Enum.reduce(1..50, before, fn n, acc ->
        State.put(acc, "ships", "s#{n}", ship("s#{n}", n * 100))
      end)

    GameRows.write(CountingRepo, "world", before, changed)
    written = sql()

    assert length(written) == 1, "expected one batched statement, got #{length(written)}"
    assert hd(written) =~ "INSERT INTO game_ships"
    assert hd(written) =~ "ON CONFLICT"
  end

  test "inserting many rows of one kind issues one statement" do
    before = %{entities: %{}}

    changed =
      Enum.reduce(1..50, before, fn n, acc ->
        State.put(acc, "ships", "s#{n}", ship("s#{n}", 0))
      end)

    GameRows.write(CountingRepo, "world", before, changed)
    assert [statement] = sql()
    refute statement =~ "ON CONFLICT"
  end

  test "deleting many rows of one kind issues one statement per table" do
    before = world(50, 0)

    changed =
      Enum.reduce(1..50, before, fn n, acc -> State.delete(acc, "ships", "s#{n}") end)

    GameRows.write(CountingRepo, "world", before, changed)
    written = sql()

    # Owned cargo holdings are cleared before the rows they reference, both batched: the
    # count tracks tables touched, never the fifty rows.
    assert length(written) == 2
    assert Enum.any?(written, &(&1 =~ "DELETE FROM game_cargo_holdings WHERE world_id=$1"))
    assert Enum.any?(written, &(&1 =~ "DELETE FROM game_ships"))
  end

  test "rows that already exist are still written before new ones" do
    before = world(1, 0)

    changed =
      before
      |> State.put("ships", "s1", ship("s1", 500))
      |> State.put("ships", "fresh", ship("fresh", 0))

    GameRows.write(CountingRepo, "world", before, changed)

    assert [{update, existing_params}, {insert, new_params}] = statements()
    assert update =~ "ON CONFLICT"
    refute insert =~ "ON CONFLICT"
    assert "s1" in existing_params
    assert "fresh" in new_params
  end

  defp batch(n),
    do: %{
      "lot_id" => "lot#{n}",
      "quantity" => 10,
      "expires_ms" => 999,
      "good" => "rice",
      "unit_cost" => 5
    }

  defp laden(count) do
    %{
      entities: %{
        "ships" => Map.new(1..count, &{"s#{&1}", Map.put(ship("s#{&1}", 0), "cargo", full())})
      }
    }
  end

  defp full, do: Enum.map(1..10, &batch/1)

  # Cargo leaves a hold oldest first, so the head is the case production runs; the tail
  # is the case a test reaches for. They must cost the same.
  defp oldest, do: tl(full())
  defp newest, do: List.update_at(full(), 9, &%{&1 | "quantity" => 7})

  defp cost(ships, cargo) do
    before = laden(ships)

    changed =
      Enum.reduce(1..ships, before, fn n, acc ->
        State.put(acc, "ships", "s#{n}", Map.put(ship("s#{n}", 0), "cargo", cargo.()))
      end)

    GameRows.write(CountingRepo, "world", before, changed)
    length(sql())
  end

  test "changing cargo on many ships issues one statement per table" do
    before = laden(50)

    changed =
      Enum.reduce(1..50, before, fn n, acc ->
        State.put(acc, "ships", "s#{n}", Map.put(ship("s#{n}", 0), "cargo", newest()))
      end)

    GameRows.write(CountingRepo, "world", before, changed)
    written = sql()

    # The ship rows, the lot identity check, the holdings and their pruning.
    assert length(written) == 4, "expected batched children, got #{length(written)} statements"
    assert Enum.count(written, &(&1 =~ "INSERT INTO game_cargo_holdings")) == 1
    assert Enum.count(written, &(&1 =~ "FROM game_cargo_lots")) == 1
    assert Enum.count(written, &(&1 =~ "DELETE FROM game_cargo_holdings")) == 1
  end

  # Comparing two fleet sizes catches a round trip per row without anyone having to guess
  # the right ceiling for one size, which is what a hardcoded count really asserts.
  test "cargo writes cost the same for ten ships as for a hundred" do
    assert cost(10, &newest/0) == cost(100, &newest/0)
    assert cost(10, &oldest/0) == cost(100, &oldest/0)
  end

  test "consuming the oldest batch costs no more round trips than changing the newest" do
    # Renumbering every survivor makes those rows genuinely dirty. What must not grow
    # with them is the number of statements it takes to write them.
    assert cost(50, &oldest/0) == cost(50, &newest/0)
  end

  defp market(stock) do
    %{
      "port" => "Jakarta",
      "good" => "lumber",
      "merchant" => false,
      "seller" => true,
      "buyer" => false,
      "stock" => stock,
      "demand" => 0,
      "budget" => 0,
      "last_production" => 0
    }
  end

  defp market_cost(markets) do
    before = %{
      entities: %{"markets" => Map.new(1..markets, &{"m#{&1}", market(10)})},
      market_versions: Map.new(1..markets, &{"m#{&1}", 3})
    }

    changed =
      Enum.reduce(1..markets, before, fn n, acc ->
        State.put(acc, "markets", "m#{n}", market(11))
      end)

    GameRows.write(CountingRepo, "world", before, changed)
    length(sql())
  end

  # Every market changes on a tick that crosses a replenishment interval, so the version
  # check is the statement most exposed to a round trip per row.
  test "market version checks cost the same for ten markets as for a hundred" do
    assert market_cost(10) == market_cost(100)
  end
end
