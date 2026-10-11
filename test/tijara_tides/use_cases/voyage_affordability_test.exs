defmodule TijaraTides.UseCases.VoyageAffordabilityTest do
  use ExUnit.Case, async: false
  alias TijaraTides.Domain.{Markets, Visibility}
  alias TijaraTides.UseCases.{GameQueries, VoyageOpportunities}

  test "quantity searches check funding without evaluating full profit at every step" do
    {state, catalogue} = TijaraTides.CommandFuzzer.fixture()
    account = state.entities["accounts"]["account"]

    view = %{
      public: Visibility.public(state, catalogue),
      private: Visibility.private(state, account),
      markets: Markets.quotes(state, catalogue)
    }

    view = put_in(view, [:private, "company", "cash"], 100_000_000)
    ship = view.private["ships"]["company:1"]
    functions = for name <- [:funded?, :evaluate], do: {VoyageOpportunities, name, 2}

    # Count work rather than wall time, which depends on the host and test load.
    Code.ensure_loaded!(VoyageOpportunities)

    try do
      for mfa <- functions,
          do: assert(:erlang.trace_pattern(mfa, true, [:local, :call_count]) == 1)

      matrix = GameQueries.destination_matrix(%{catalogue: catalogue}, view, ship)
      assert Enum.any?(matrix.rows, &(&1.plan && &1.plan.purchases != []))
      [funding, profit] = Enum.map(functions, &call_count/1)
      assert funding > profit, "#{funding} funding checks vs #{profit} full profit evaluations"
      assert profit > 0
    after
      for mfa <- functions, do: :erlang.trace_pattern(mfa, false, [:local, :call_count])
    end
  end

  defp call_count(mfa) do
    {:call_count, count} = :erlang.trace_info(mfa, :call_count)
    count
  end
end
