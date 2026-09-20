defmodule TijaraTides.Infrastructure.Persistence.FinancialLedgerBatchingTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Infrastructure.Persistence.FinancialLedger

  # Cargo splits on every partial sale, so a busy tick creates lots in bulk. A statement
  # per lot costs a round trip per lot inside the transaction the whole tick commits in.
  defmodule CountingRepo do
    def query!(sql, params) do
      send(self(), {:sql, sql, params})
      %{rows: [], num_rows: 1}
    end
  end

  defp statements do
    receive do
      {:sql, sql, params} -> [{sql, params} | statements()]
    after
      0 -> []
    end
  end

  defp lot(n, parent \\ nil),
    do: %{
      "id" => "lot#{n}",
      "parent_lot_id" => parent,
      "good" => "rice",
      "quantity" => 10,
      "expires_ms" => nil,
      "created_ms" => 0
    }

  defp write(lots) do
    FinancialLedger.write_lots(CountingRepo, "world", %{new_lots: []}, %{new_lots: lots})
    statements()
  end

  test "writing many new lots issues one statement" do
    written = write(Enum.map(1..50, &lot/1))

    assert [{statement, params}] = written
    assert statement =~ "INSERT INTO game_cargo_lots"
    assert "lot1" in params and "lot50" in params
  end

  test "new lots cost the same for ten as for a hundred" do
    assert length(write(Enum.map(1..10, &lot/1))) ==
             length(write(Enum.map(1..100, &lot/1)))
  end

  test "a split parent and its children are written together" do
    # PostgreSQL checks a self-referencing foreign key at the end of the statement, so
    # both may go in one. Keeping them in one statement is what makes that true.
    written = write([lot(1), lot(2, "lot1"), lot(3, "lot1")])

    assert [{_, params}] = written
    assert Enum.count(params, &(&1 == "lot1")) == 3
  end
end
