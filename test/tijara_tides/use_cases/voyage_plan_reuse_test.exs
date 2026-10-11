defmodule TijaraTides.UseCases.VoyagePlanReuseTest do
  use ExUnit.Case, async: false
  alias TijaraTides.Domain.{Markets, Visibility}
  alias TijaraTides.UseCases.VoyageOpportunities

  test "identical prefixes share purchase searches and identical tanker plans share onward searches" do
    {state, catalogue} = TijaraTides.CommandFuzzer.fixture()

    view = %{
      public: Visibility.public(state, catalogue),
      private: Visibility.private(state, state.entities["accounts"]["account"]),
      markets: Markets.quotes(state, catalogue)
    }

    catalogue =
      catalogue
      |> Map.put("ports", Map.take(catalogue["ports"], ["Singapore", "Colombo"]))
      |> Map.put("goods", Map.take(catalogue["goods"], ["crude_oil", "refined_fuel"]))

    ship =
      Map.merge(view.private["ships"]["company:1"], %{"class" => "tanker", "port" => "Singapore"})

    view =
      view
      |> put_in([:private, "company", "cash"], 100_000_000)
      |> put_in([:private, "ships", ship["id"]], ship)

    view =
      Enum.reduce(Map.keys(catalogue["goods"]), view, fn good, view ->
        view
        |> update_in(
          [:markets, "Singapore|" <> good],
          &Map.merge(&1, %{"stock" => 10, "ask" => 1_000_000_000})
        )
        |> update_in(
          [:markets, "Colombo|" <> good],
          &Map.merge(&1, %{
            "stock" => 0,
            "demand" => 10,
            "bid" => 2_000_000_000,
            "buyer_budget" => 20_000_000_000
          })
        )
      end)

    functions = [{VoyageOpportunities, :add_purchase, 3}, {VoyageOpportunities, :after_voyage, 3}]
    Code.ensure_loaded!(VoyageOpportunities)

    try do
      for mfa <- functions,
          do: assert(:erlang.trace_pattern(mfa, true, [:local, :call_count]) == 1)

      result = VoyageOpportunities.tanker_estimate(catalogue, view, ship, "Colombo")
      assert result.purchases == []
      assert result.onward == nil
      assert result.combined_profit == result.profit

      assert Enum.map(functions, fn mfa ->
               {:call_count, count} = :erlang.trace_info(mfa, :call_count)
               count
             end) == [2, 1]
    after
      for mfa <- functions, do: :erlang.trace_pattern(mfa, false, [:local, :call_count])
    end
  end
end
