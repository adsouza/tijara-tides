defmodule TijaraTides.UseCases.ReportQueriesTest do
  use ExUnit.Case, async: true
  alias TijaraTides.UseCases.ReportQueries
  @quarter 604_800_000
  defmodule Store do
    @behaviour TijaraTides.UseCases.ReportStore
    def page(fun, selection, owner, expected), do: fun.(selection, owner, expected)
  end

  test "selection enforces retention and bounded pages without building historical dropdown lists" do
    assert %{selected: 7, minimum: 7, limit: 10, page: 0} =
             ReportQueries.selection(10 * @quarter, %{"index" => 0})

    assert %{selected: 7, minimum: 7} =
             ReportQueries.selection(10 * @quarter, %{"index" => 0, "metric" => "roi"})

    assert %{selected: 0, minimum: 0} =
             ReportQueries.selection(40 * @quarter, %{"period" => "year", "index" => 0})

    assert %{selected: 10, page: 100_000} =
             ReportQueries.selection(10 * @quarter, %{"index" => 99999, "page" => 9_999_999})

    assert %{selected: 0, page: 0} = ReportQueries.selection(0, %{"index" => "bad", "page" => -1})
  end

  test "owner identity is authenticated and public results exclude accounting details" do
    game = %{
      clock_ms: 0,
      epoch: 1,
      revision: 2,
      entities: %{
        "accounts" => %{"owner" => %{"id" => "owner"}},
        "sessions" => %{"secret" => %{"account_id" => "owner", "expires_at" => 100}}
      }
    }

    for {token, wall, owner} <- [{"secret", 1, "owner"}, {"secret", 101, nil}, {nil, 1, nil}] do
      store = fn selection, authenticated, expected ->
        assert selection.limit == 10
        assert authenticated == owner
        assert expected.revision == 2
        row = %{"name" => "Public", "profit" => 2, "capital_ms" => 100, "revenue" => 500}

        {:ok,
         %{
           ranked: [row],
           provisional: [],
           own: [],
           ranked_count: 1,
           provisional_count: 0,
           own_count: 0
         }}
      end

      assert {:ok, page} = ReportQueries.run(game, token, wall, %{}, {Store, store})
      refute Map.has_key?(hd(page.ranked), "revenue")
      refute Map.has_key?(hd(page.ranked), "capital_ms")
    end
  end
end
