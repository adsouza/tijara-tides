defmodule TijaraTides.CommandFuzzer.StoreTest do
  use ExUnit.Case, async: true
  alias TijaraTides.CommandFuzzer.Store

  test "receipt and commit callbacks receive exact arguments and propagate failures" do
    ops = %{
      receipt: fn account, id, fingerprint -> {:observed, account, id, fingerprint} end,
      commit: fn before, after_state, receipt -> {:observed, before, after_state, receipt} end
    }

    assert Store.receipt(ops, :account, :request, :fingerprint) ==
             {:observed, :account, :request, :fingerprint}

    assert Store.commit(ops, :before, :after, :receipt) == {:observed, :before, :after, :receipt}

    failing = %{
      receipt: fn _, _, _ -> {:error, :storage_failure} end,
      commit: fn _, _, _ -> {:error, :storage_failure} end
    }

    assert Store.receipt(failing, :account, :request, :fingerprint) == {:error, :storage_failure}
    assert Store.commit(failing, :before, :after, :receipt) == {:error, :storage_failure}
  end

  test "lot allocation returns exactly the requested count with no duplicates across calls" do
    assert Store.allocate_lot_ids(nil, 0) == []
    first = Store.allocate_lot_ids(nil, 1)
    second = Store.allocate_lot_ids(nil, 3)
    assert length(first) == 1
    assert length(second) == 3
    assert MapSet.size(MapSet.new(first ++ second)) == 4
    assert Enum.all?(first ++ second, &String.starts_with?(&1, "fixture-lot:"))
  end

  test "reload and restore preserve the supplied fixture rather than incorporating other state" do
    game = %{revision: 7, entities: %{"companies" => %{"company" => %{"cash" => 100}}}}
    assert Store.reload(nil, game) == {:ok, game}
    assert Store.restore(nil, game, %{revision: 99, entities: %{}}) == game
  end
end
