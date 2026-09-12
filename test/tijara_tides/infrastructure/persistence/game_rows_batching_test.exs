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
      %{rows: [], num_rows: 1}
    end
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

  test "deleting many rows of one kind issues one statement" do
    before = world(50, 0)

    changed =
      Enum.reduce(1..50, before, fn n, acc -> State.delete(acc, "ships", "s#{n}") end)

    GameRows.write(CountingRepo, "world", before, changed)
    written = sql()

    assert length(written) == 1
    assert hd(written) =~ "DELETE FROM game_ships"
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
end
