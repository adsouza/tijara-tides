defmodule TijaraTides.Domain.QueueMarginTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{AccountWorld, BerthFixture, Game, State, Trade}
  alias TijaraTides.Domain.Services.BerthAllocation

  setup do
    cat =
      TijaraTides.Infrastructure.GameCatalogue.all()
      |> put_in(["ports", "Jakarta", "berth_count"], 1)

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

    %{state: s, cat: cat}
  end

  defp account(s), do: Game.get(s, "accounts", "a")

  defp ask(s, cat),
    do: TijaraTides.Domain.PortCargoMarketWorld.quote(s, cat, "Jakarta", "lumber")["ask"]

  defp buy(s, cat, fields \\ %{}),
    do:
      struct!(
        %Trade{
          side: "buy",
          ship_id: "aco:1",
          good: "lumber",
          quantity: 1,
          limit: ask(s, cat),
          destination: "Singapore"
        },
        fields
      )

  defp submit(s, cat, trade), do: BerthAllocation.submit(s, account(s), trade, cat)

  # The ship is mid-handling after an immediate purchase: the first queue path.
  defp loading(s, cat) do
    {:ok, s, reply} = submit(s, cat, buy(s, cat))
    refute reply["queued"]
    assert Game.get(s, "ships", "aco:1")["status"] == "loading"
    s
  end

  # Another ship holds the only berth's queue ticket: the second queue path.
  defp berth_busy(s, _cat), do: BerthAllocation.enqueue(s, "aco:2")

  defp default(s, side, bps) do
    {:ok, s, _} = AccountWorld.set_queue_margin(s, account(s), side, bps)
    s
  end

  defp pending_limit(s), do: Game.get(s, "ships", "aco:1")["pending_limit"]

  for path <- [:loading, :berth_busy] do
    @path path

    test "#{path}: without a margin or default the trade is refused untouched", c do
      s = apply(__MODULE__, :__path__, [@path, c.state, c.cat])
      assert submit(s, c.cat, buy(s, c.cat)) == {:error, :queue_margin_required}
    end

    test "#{path}: an explicit margin widens the stored limit", c do
      s = apply(__MODULE__, :__path__, [@path, c.state, c.cat])
      trade = buy(s, c.cat, margin_bps: 200)
      assert {:ok, next, %{"queued" => true}} = submit(s, c.cat, trade)
      assert pending_limit(next) == Trade.queued_limit("buy", trade.limit, 200)
      assert pending_limit(next) > trade.limit
      assert AccountWorld.queue_margin(next, "a", "buy") == nil
    end

    test "#{path}: a saved default applies, and an explicit margin overrides it", c do
      s = apply(__MODULE__, :__path__, [@path, c.state, c.cat]) |> default("buy", 300)
      trade = buy(s, c.cat)
      assert {:ok, next, %{"queued" => true}} = submit(s, c.cat, trade)
      assert pending_limit(next) == Trade.queued_limit("buy", trade.limit, 300)

      assert {:ok, next, %{"queued" => true}} = submit(s, c.cat, %{trade | margin_bps: 100})
      assert pending_limit(next) == Trade.queued_limit("buy", trade.limit, 100)
    end

    test "#{path}: saving a margin stores that side's default with the queued trade", c do
      s = apply(__MODULE__, :__path__, [@path, c.state, c.cat])
      trade = buy(s, c.cat, margin_bps: 150, save_margin: true)
      assert {:ok, next, %{"queued" => true}} = submit(s, c.cat, trade)
      assert AccountWorld.queue_margin(next, "a", "buy") == 150
      assert AccountWorld.queue_margin(next, "a", "sell") == nil
      assert pending_limit(next) == Trade.queued_limit("buy", trade.limit, 150)
    end
  end

  def __path__(:loading, s, cat), do: loading(s, cat)
  def __path__(:berth_busy, s, cat), do: berth_busy(s, cat)

  test "an immediate trade ignores its margin but still saves a chosen default", c do
    s = c.state
    trade = buy(s, c.cat, margin_bps: 500, save_margin: true)
    assert {:ok, next, reply} = submit(s, c.cat, trade)
    refute reply["queued"]
    assert Game.get(next, "ships", "aco:1")["status"] == "loading"
    assert pending_limit(next) == nil
    assert AccountWorld.queue_margin(next, "a", "buy") == 500

    # The margin never loosens an immediate trade: one cent short of the price is
    # refused even though the widened limit would cover it, and nothing is saved.
    short = %{trade | limit: trade.limit - 1}
    assert Trade.queued_limit("buy", short.limit, 500) >= ask(s, c.cat)
    assert submit(s, c.cat, short) == {:error, :price_changed}

    {s, good} = with_sellable_cargo(s, c.cat)
    bid = TijaraTides.Domain.PortCargoMarketWorld.quote(s, c.cat, "Jakarta", good)["bid"]

    sell = %Trade{
      side: "sell",
      ship_id: "aco:1",
      good: good,
      quantity: 5,
      limit: bid + 1,
      destination: nil,
      margin_bps: 500,
      save_margin: true
    }

    assert Trade.queued_limit("sell", sell.limit, 500) <= bid
    assert submit(s, c.cat, sell) == {:error, :price_changed}
    assert {:ok, sold, reply} = submit(s, c.cat, %{sell | limit: bid})
    refute reply["queued"]
    assert AccountWorld.queue_margin(sold, "a", "sell") == 500
  end

  test "each side resolves only its own default", c do
    s = loading(c.state, c.cat) |> default("buy", 300)
    {s, good} = with_sellable_cargo(s, c.cat)
    bid = TijaraTides.Domain.PortCargoMarketWorld.quote(s, c.cat, "Jakarta", good)["bid"]

    sell = %Trade{
      side: "sell",
      ship_id: "aco:1",
      good: good,
      quantity: 5,
      limit: bid,
      destination: nil
    }

    assert submit(s, c.cat, sell) == {:error, :queue_margin_required}

    s = default(s, "sell", 400)
    assert {:ok, next, %{"queued" => true}} = submit(s, c.cat, sell)
    assert pending_limit(next) == Trade.queued_limit("sell", bid, 400)
    assert pending_limit(next) < bid
  end

  describe "a queued trade fills exactly when its widened limit covers the price" do
    # Queue at today's price, move the market against the trade, then let the berth
    # free up. The smallest covering margin fills; one basis point less stays queued.
    defp settle(s, cat, trade, margin) do
      s = berth_busy(s, cat)
      {:ok, s, %{"queued" => true}} = submit(s, cat, %{trade | margin_bps: margin})
      s
    end

    defp release_berth(s) do
      s
      |> BerthFixture.update("aco:2", %{berth_queued_ms: nil})
      |> BerthFixture.update("aco:1", %{berth_queued_ms: nil, berth_retry_ms: 300_000})
    end

    defp smallest_covering(side, limit, price) do
      Enum.find(0..1_000, fn m ->
        q = Trade.queued_limit(side, limit, m)
        if side == "buy", do: q >= price, else: q <= price
      end)
    end

    test "buy: the ask rises after queueing", c do
      s = c.state
      trade = buy(s, c.cat)
      market = Game.get(s, "markets", "Jakarta|lumber")

      moved = fn s ->
        State.put(s, "markets", "Jakarta|lumber", %{market | "stock" => market["stock"] - 30})
      end

      raised = ask(moved.(s), c.cat)
      assert raised > trade.limit
      m = smallest_covering("buy", trade.limit, raised)
      assert m > 0 and m <= 1_000
      assert Trade.queued_limit("buy", trade.limit, m - 1) < raised

      for {margin, filled?} <- [{m, true}, {m - 1, false}] do
        s = s |> settle(c.cat, trade, margin) |> moved.() |> release_berth()
        assert ask(s, c.cat) == raised
        next = BerthAllocation.advance(s, c.cat)
        ship = Game.get(next, "ships", "aco:1")
        assert is_nil(ship["pending_side"]) == filled?, "margin #{margin}"
        assert ship["status"] == "loading" == filled?
      end
    end

    test "sell: the bid falls after queueing", c do
      {s, good} = with_sellable_cargo(c.state, c.cat)
      quote = fn s -> TijaraTides.Domain.PortCargoMarketWorld.quote(s, c.cat, "Jakarta", good) end
      bid = quote.(s)["bid"]

      trade = %Trade{
        side: "sell",
        ship_id: "aco:1",
        good: good,
        quantity: 5,
        limit: bid,
        destination: nil
      }

      market = Game.get(s, "markets", "Jakarta|" <> good)

      moved = fn s ->
        State.put(s, "markets", "Jakarta|" <> good, %{market | "demand" => market["demand"] - 30})
      end

      lowered = quote.(moved.(s))["bid"]
      assert lowered < bid
      m = smallest_covering("sell", bid, lowered)
      assert m > 0 and m <= 1_000
      assert Trade.queued_limit("sell", bid, m - 1) > lowered

      for {margin, filled?} <- [{m, true}, {m - 1, false}] do
        s = s |> settle(c.cat, trade, margin) |> moved.() |> release_berth()
        next = BerthAllocation.advance(s, c.cat)
        ship = Game.get(next, "ships", "aco:1")
        assert is_nil(ship["pending_side"]) == filled?, "margin #{margin}"
      end
    end
  end

  # A good Jakarta buys, with 20 lots of it aboard the first ship.
  defp with_sellable_cargo(s, cat) do
    good =
      s.entities["markets"]
      |> Enum.filter(fn {key, m} ->
        g = String.replace_prefix(key, "Jakarta|", "")

        String.starts_with?(key, "Jakarta|") and m["buyer"] and m["demand"] > 40 and
          cat["goods"][g]["manual"] and cat["goods"][g]["hold"] == "dry"
      end)
      |> Enum.map(fn {key, _} -> String.replace_prefix(key, "Jakarta|", "") end)
      |> Enum.sort()
      |> hd()

    {s, lot} = TijaraTides.Domain.CargoLots.create(s, good, 20, nil)
    shelf = cat["goods"][good]["shelf_ms"]

    batch =
      Map.merge(lot, %{
        "good" => good,
        "unit_cost" => 100,
        "expires_ms" => if(shelf > 0, do: s.clock_ms + shelf)
      })
      |> TijaraTides.Domain.Ship.CargoRows.decode()
      |> TijaraTides.Domain.Ship.CargoRows.encode()

    ship = Game.get(s, "ships", "aco:1")
    {State.put(s, "ships", "aco:1", %{ship | "cargo" => ship["cargo"] ++ [batch]}), good}
  end
end
