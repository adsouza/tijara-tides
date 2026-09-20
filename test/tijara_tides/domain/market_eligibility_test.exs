defmodule TijaraTides.Domain.MarketEligibilityTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{Game, PortCargoMarket, PortCargoMarketWorld, State}
  alias TijaraTides.Infrastructure.GameCatalogue
  alias TijaraTides.UseCases.GameQueries

  setup do
    catalogue = GameCatalogue.all()
    game = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, catalogue)
    %{game: game, catalogue: catalogue}
  end

  test "every catalogue quote respects market roles and advertised supply is releasable", c do
    quotes = PortCargoMarketWorld.quotes(c.game, c.catalogue)

    feedstocks =
      Enum.filter(State.entities(c.game, "markets"), fn {_, row} ->
        row["feedstock"] && not row["seller"] && row["stock"] > 0
      end)

    assert feedstocks != []

    for {id, row} <- State.entities(c.game, "markets") do
      quote = quotes[id]
      assert quote == PortCargoMarketWorld.quote(c.game, c.catalogue, row["port"], row["good"])
      if not row["seller"], do: assert(quote["stock"] == 0, id)
      if not row["buyer"], do: assert(quote["demand"] == 0, id)

      if quote["manual"] and quote["stock"] > 0 do
        {_, cargo} =
          PortCargoMarketWorld.release_stock(
            c.game,
            row["port"],
            row["good"],
            quote["stock"],
            quote["ask"],
            c.catalogue["goods"][row["good"]]
          )

        assert Enum.sum(Enum.map(cargo, & &1["quantity"])) == quote["stock"], id
      end
    end
  end

  test "quote eligibility holds independently of physical stock, demand and budget", c do
    market = PortCargoMarketWorld.fetch(c.game, "Tangier", "aluminium_scrap")

    for seller <- [false, true], buyer <- [false, true] do
      market = %{market | seller: seller, buyer: buyer, stock: 480, demand: 20, budget: 1000}
      quote = PortCargoMarket.quote(market, c.catalogue)
      assert quote["stock"] == if(seller, do: 480, else: 0)
      assert quote["demand"] == if(buyer, do: 20, else: 0)
      assert quote["buyer_budget"] == if(buyer, do: 1000, else: 0)
      assert market.stock == 480
    end
  end

  test "Tangier factory feedstock cannot be bought through UI limits or direct commands", c do
    {:ok, game, _} = Game.seed_invite(c.game, "invite")
    {:ok, game, _} = Game.redeem(game, "invite", "session", %{id: "account", wall_ms: 0})

    {:ok, game, _} =
      TijaraTides.CompanyFixture.execute(
        game,
        Game.get(game, "accounts", "account"),
        %{"action" => "company", "name" => "Repro", "port" => "Tangier", "package" => "bulk"},
        %{id: "company", catalogue: c.catalogue},
        c.catalogue
      )

    market = Game.get(game, "markets", "Tangier|aluminium_scrap")
    game = State.put(game, "markets", "Tangier|aluminium_scrap", %{market | "stock" => 480})
    account = Game.get(game, "accounts", "account")
    ship = Game.get(game, "ships", "company:1")

    view = %{
      private: Game.private(game, account),
      public: Game.public(game, c.catalogue),
      markets: PortCargoMarketWorld.quotes(game, c.catalogue)
    }

    assert GameQueries.trade_limits(view, ship, "São Paulo", c.catalogue)[
             {"buy", "aluminium_scrap"}
           ] == 0

    for quantity <- [1, 50, 480] do
      command = %{
        "action" => "buy",
        "ship" => ship["id"],
        "good" => "aluminium_scrap",
        "quantity" => quantity,
        "limit" => 1_000_000,
        "destination" => "São Paulo"
      }

      assert {:error, :insufficient_supply} =
               Game.execute(game, account, command, %{id: "buy"}, c.catalogue)
    end

    # Reject a fabricated sale to an exporter too, before the buyer aggregate raises.
    market = %{market | "seller" => true, "buyer" => false, "demand" => 500}
    game = State.put(game, "markets", "Tangier|aluminium_scrap", market)

    assert {:error, :insufficient_demand} =
             Game.execute(
               game,
               account,
               %{
                 "action" => "sell",
                 "ship" => ship["id"],
                 "good" => "aluminium_scrap",
                 "quantity" => 1,
                 "limit" => 0
               },
               %{id: "sell"},
               c.catalogue
             )
  end
end
