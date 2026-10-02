defmodule TijaraTides.UseCases.TradeOffersTest do
  # Offered trade quantities use the purchase command's own admission and funding
  # rules, including the current visit's budget: the offer is accepted and one lot
  # more is refused, and nothing is offered that the berth would refuse.
  use ExUnit.Case, async: true

  alias TijaraTides.Domain.{AutomationWorld, CompanyFinanceWorld, Game, Markets, Trade}
  alias TijaraTides.Domain.Visibility
  alias TijaraTides.Domain.Services.{BerthAllocation, TradeSettlement}
  alias TijaraTides.UseCases.GameQueries

  defp world(port \\ "Jakarta", package \\ "general") do
    cat = TijaraTides.UseCases.Game.definitions().catalogue
    s = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, cat)
    {:ok, s, _} = Game.seed_invite(s, "invite")
    {:ok, s, _} = Game.redeem(s, "invite", "session", %{id: "a", wall_ms: 0})

    {:ok, s, _} =
      TijaraTides.CompanyFixture.create_company(
        s,
        Game.get(s, "accounts", "a"),
        "a",
        port,
        package,
        %{id: "aco", catalogue: cat}
      )

    s
  end

  defp cat, do: TijaraTides.UseCases.Game.definitions().catalogue
  defp account(s), do: Game.get(s, "accounts", "a")

  defp view(s),
    do: %{
      public: Visibility.public(s, cat()),
      private: Visibility.private(s, account(s)),
      markets: Markets.quotes(s, cat())
    }

  defp offer(s, side, good, destination) do
    v = view(s)
    GameQueries.trade_limits(v, v.private["ships"]["aco:1"], destination, cat())[{side, good}]
  end

  defp trade(side, good, n, limit, destination),
    do: %Trade{
      side: side,
      ship_id: "aco:1",
      good: good,
      quantity: n,
      limit: limit,
      destination: destination
    }

  defp validate(s, good, n),
    do:
      TradeSettlement.validate(
        s,
        account(s),
        trade("buy", good, n, view(s).markets["Jakarta|" <> good]["ask"], "Athens"),
        cat()
      )

  defp submit(s, side, good, n, destination, port \\ "Jakarta"),
    do:
      BerthAllocation.submit(
        s,
        account(s),
        trade(side, good, n, view(s).markets[port <> "|" <> good]["ask"], destination),
        cat()
      )

  defp available(s, n) do
    company = Game.get(s, "companies", "aco")
    delta = n - company["cash"] + company["reserved"]

    CompanyFinanceWorld.post(s, "aco", "test_funds", [
      {"cash_available", delta},
      {"capital", -delta}
    ])
  end

  defp budget(s, configured, amount, skip),
    do:
      AutomationWorld.reserve_visit(
        s,
        %{
          id: "vb",
          company_id: "aco",
          ship_id: "aco:1",
          stop_id: nil,
          port: "Jakarta",
          configured: configured,
          visit: 1
        },
        amount,
        skip
      )

  test "a skip decision for this visit offers no purchases" do
    s = world() |> available(2_000_000) |> budget(nil, 0, true)

    for good <- ["lumber", "iron_ore"] do
      assert offer(s, "buy", good, "Athens") == 0
      assert validate(s, good, 1) == {:error, :insufficient_cash}
    end
  end

  test "a strict visit budget offers exactly what the purchase command accepts" do
    s = world() |> available(2_000_000) |> budget(1_000_000, 1_000_000, false)

    for good <- ["lumber", "iron_ore", "fruit"] do
      n = offer(s, "buy", good, "Athens")
      assert n > 0
      assert validate(s, good, n) == :ok
      refute validate(s, good, n + 1) == :ok
    end
  end

  test "a trade queued at the berth suppresses further offers" do
    s = world()
    {:ok, s, _} = submit(s, "buy", "lumber", 100, "Athens")
    {:ok, s, %{"queued" => true}} = submit(s, "buy", "lumber", 10, "Athens")

    assert offer(s, "buy", "iron_ore", "Athens") == 0
    assert submit(s, "buy", "iron_ore", 1, "Athens") == {:error, :berth_order_pending}
  end

  test "a tanker that is handling cargo is offered no purchases" do
    s = world("Abu Dhabi", "oil")

    destination =
      cat()["routes"]
      |> Map.keys()
      |> Enum.filter(&String.starts_with?(&1, "Abu Dhabi|"))
      |> Enum.map(&String.replace_prefix(&1, "Abu Dhabi|", ""))
      |> Enum.sort()
      |> hd()

    {:ok, s, _} = submit(s, "buy", "crude_oil", 20, destination, "Abu Dhabi")
    assert Game.get(s, "ships", "aco:1")["status"] == "loading"

    assert offer(s, "buy", "crude_oil", destination) == 0

    assert submit(s, "buy", "crude_oil", 1, destination, "Abu Dhabi") ==
             {:error, :tanker_purchase_handling}
  end

  test "a sale offer stops at what the buyer's budget pays for, as the sale command does" do
    s = world()

    {good, quote} =
      view(s).markets
      |> Enum.filter(fn {key, q} ->
        String.starts_with?(key, "Jakarta|") and q["manual"] and q["demand"] > 10 and
          q["bid"] > 0 and
          cat()["goods"][String.replace_prefix(key, "Jakarta|", "")]["hold"] == "dry"
      end)
      |> Enum.sort()
      |> hd()
      |> then(fn {key, q} -> {String.replace_prefix(key, "Jakarta|", ""), q} end)

    {s, lot} = TijaraTides.Domain.CargoLots.create(s, good, 300, nil)
    shelf = cat()["goods"][good]["shelf_ms"]

    batch =
      Map.merge(lot, %{
        "good" => good,
        "unit_cost" => 100,
        "expires_ms" => if(shelf > 0, do: s.clock_ms + shelf)
      })
      |> TijaraTides.Domain.Ship.CargoRows.decode()
      |> TijaraTides.Domain.Ship.CargoRows.encode()

    ship = Game.get(s, "ships", "aco:1")
    market = Game.get(s, "markets", "Jakarta|" <> good)

    s =
      s
      |> TijaraTides.Domain.State.put("ships", "aco:1", %{ship | "cargo" => [batch]})
      |> TijaraTides.Domain.State.put("markets", "Jakarta|" <> good, %{
        market
        | "budget" => quote["bid"] * 7 + div(quote["bid"], 2)
      })

    sell = fn n ->
      TradeSettlement.validate(
        s,
        account(s),
        trade("sell", good, n, quote["bid"], "Athens"),
        cat()
      )
    end

    assert offer(s, "sell", good, "Athens") == 7
    assert sell.(7) == :ok
    assert sell.(8) == {:error, :insufficient_demand}
  end
end
