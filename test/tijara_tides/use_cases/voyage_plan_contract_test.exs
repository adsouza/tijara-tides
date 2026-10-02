defmodule TijaraTides.UseCases.VoyagePlanContractTest do
  # A voyage plan describes cargo the purchase command would actually load: the
  # same lots, aged at the ship's hold rate. A planned sale must still succeed
  # when the ship arrives.
  use ExUnit.Case, async: true

  alias TijaraTides.Domain.{Commands, CompanyFinanceWorld, Game, Markets, State, Visibility}
  alias TijaraTides.UseCases.VoyageOpportunities

  setup do
    definitions = TijaraTides.UseCases.Game.definitions()
    cat = definitions.catalogue
    s = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, cat)
    {:ok, s, _} = Game.seed_invite(s, "invite")
    {:ok, s, _} = Game.redeem(s, "invite", "session", %{id: "a", wall_ms: 0})

    {:ok, s, _} =
      TijaraTides.CompanyFixture.create_company(
        s,
        Game.get(s, "accounts", "a"),
        "a",
        "Jakarta",
        "general",
        %{id: "aco", catalogue: cat}
      )

    company = Game.get(s, "companies", "aco")
    delta = 100_000_000 - company["cash"] + company["reserved"]

    s =
      CompanyFinanceWorld.post(s, "aco", "test_funds", [
        {"cash_available", delta},
        {"capital", -delta}
      ])

    %{s: s, cat: cat}
  end

  defp view(s, cat) do
    account = Game.get(s, "accounts", "a")

    %{
      public: Visibility.public(s, cat),
      private: Visibility.private(s, account),
      markets: Markets.quotes(s, cat)
    }
  end

  defp command(s, cat, command) do
    Commands.execute(s, Game.get(s, "accounts", "a"), command, %{id: "cmd", catalogue: cat})
  end

  defp seafood_plan(s, cat) do
    view = view(s, cat)
    # Only seafood is on offer, so the planner must decide whether it survives the voyage.
    only = %{view | markets: Map.filter(view.markets, fn {k, _} -> k =~ "|seafood" end)}
    {view, VoyageOpportunities.estimate(cat, only, view.private["ships"]["aco:1"], "Tokyo")}
  end

  test "seafood that would spoil before arrival is not planned", c do
    {_view, plan} = seafood_plan(c.s, c.cat)
    life = c.cat["goods"]["seafood"]["shelf_ms"]
    assert plan.arrival > life
    assert plan.purchases == []
  end

  test "planned perishable purchases are still saleable when the ship arrives", c do
    cat = put_in(c.cat, ["goods", "seafood", "shelf_ms"], 50_000_000)
    s = Game.initialize(%{c.s | entities: Map.delete(c.s.entities, "markets")}, cat)
    {view, plan} = seafood_plan(s, cat)
    assert [%{good: "seafood", lots: n}] = plan.purchases
    assert [%{good: "seafood", lots: sold}] = plan.sales

    {:ok, bought, _} =
      command(s, cat, %{
        "action" => "buy",
        "ship" => "aco:1",
        "good" => "seafood",
        "quantity" => n,
        "limit" => view.markets["Jakarta|seafood"]["ask"],
        "destination" => "Tokyo"
      })

    sailing = Game.get(bought, "ships", "aco:1")

    arrived =
      bought
      |> State.put("ships", "aco:1", %{
        sailing
        | "port" => "Tokyo",
          "status" => "docked",
          "arrive_ms" => nil
      })
      |> Map.put(:clock_ms, plan.arrival)

    assert {:ok, _, _} =
             command(arrived, cat, %{
               "action" => "sell",
               "ship" => "aco:1",
               "good" => "seafood",
               "quantity" => sold,
               "limit" => view(arrived, cat).markets["Tokyo|seafood"]["bid"]
             })
  end

  test "at the least cash the purchase command accepts, the plan buys that many lots", c do
    for {destination, good, n} <- [{"Tangier", "lumber", 13}, {"Tokyo", "everyday_clothing", 7}] do
      ask = view(c.s, c.cat).markets["Jakarta|" <> good]["ask"]

      accepts? = fn cash ->
        s = with_cash(c.s, cash)

        TijaraTides.Domain.Services.TradeSettlement.validate(
          s,
          Game.get(s, "accounts", "a"),
          %TijaraTides.Domain.Trade{
            side: "buy",
            ship_id: "aco:1",
            good: good,
            quantity: n,
            limit: ask,
            destination: destination
          },
          c.cat
        ) == :ok
      end

      cash =
        TijaraTides.UseCases.MarketQueries.largest_trade(0, 50_000_000, &(not accepts?.(&1))) + 1

      assert accepts?.(cash) and not accepts?.(cash - 1)

      v = view(with_cash(c.s, cash), c.cat)

      only = %{
        v
        | markets: Map.filter(v.markets, fn {k, _} -> String.ends_with?(k, "|" <> good) end)
      }

      plan = VoyageOpportunities.estimate(c.cat, only, v.private["ships"]["aco:1"], destination)
      assert plan.purchases == [%{good: good, lots: n}]
    end
  end

  defp with_cash(s, n) do
    company = Game.get(s, "companies", "aco")
    delta = n - company["cash"] + company["reserved"]

    CompanyFinanceWorld.post(s, "aco", "test_funds", [
      {"cash_available", delta},
      {"capital", -delta}
    ])
  end
end
