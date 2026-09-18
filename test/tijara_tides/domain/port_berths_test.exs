defmodule TijaraTides.Domain.PortBerthsTest do
  alias TijaraTides.Domain.PortBerthsWorld
  alias TijaraTides.Domain.ShipWorld
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{Game, State, Trade, PortBerths}
  alias TijaraTides.Domain.Services.BerthAllocation

  setup do
    catalogue =
      TijaraTides.Infrastructure.GameCatalogue.all()
      |> put_in(["ports", "Jakarta", "berth_count"], 1)

    state = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, catalogue)
    {:ok, state, _} = Game.seed_invite(state, "invite")
    {:ok, state, _} = Game.redeem(state, "invite", "session", %{id: "account", wall_ms: 0})
    account = Game.get(state, "accounts", "account")

    {:ok, state, _} =
      TijaraTides.CompanyFixture.create_company(
        state,
        account,
        "Queue Company",
        "Jakarta",
        "general",
        %{id: "company", catalogue: catalogue}
      )

    %{state: state, account: Game.get(state, "accounts", "account"), catalogue: catalogue}
  end

  defp trade(id),
    do: %Trade{
      side: "buy",
      ship_id: id,
      good: "lumber",
      quantity: 1,
      limit: 1_000_000,
      destination: "Singapore"
    }

  test "a ready manual trade uses a free berth despite its own ticket or old cooldown", c do
    for fields <- [%{berth_queued_ms: 0}, %{berth_retry_ms: 300_000}] do
      s = TijaraTides.Domain.BerthFixture.update(c.state, "company:1", fields)
      {:ok, next, reply} = BerthAllocation.submit(s, c.account, trade("company:1"), c.catalogue)
      refute reply["queued"]
      assert Game.get(next, "ships", "company:1")["status"] == "loading"
      refute Game.get(next, "ships", "company:1")["berth_queued_ms"]
      refute Game.get(next, "ships", "company:1")["berth_retry_ms"]
    end
  end

  test "a recovered pending trade retries immediately without bypassing queue priority", c do
    s = ShipWorld.queue_trade(c.state, trade("company:1"))

    s =
      TijaraTides.Domain.BerthFixture.update(s, "company:1", %{
        berth_queued_ms: nil,
        berth_retry_ms: 300_000
      })

    assert BerthAllocation.pending_status(
             s,
             c.account,
             Game.get(s, "ships", "company:1"),
             c.catalogue
           ) == :berth_wait

    next = BerthAllocation.advance(s, c.catalogue)
    assert Game.get(next, "ships", "company:1")["status"] == "loading"
    refute Game.get(next, "ships", "company:1")["pending_side"]

    s = BerthAllocation.enqueue(c.state, "company:2")

    {:ok, next, %{"queued" => true}} =
      BerthAllocation.submit(s, c.account, trade("company:1"), c.catalogue)

    assert Game.get(next, "ships", "company:1")["cargo"] == []
    roomy = put_in(c.catalogue, ["ports", "Jakarta", "berth_count"], 4)
    {:ok, next, reply} = BerthAllocation.submit(s, c.account, trade("company:1"), roomy)
    refute reply["queued"]
    assert Game.get(next, "ships", "company:1")["status"] == "loading"
  end

  test "pending trade conditions are distinguished from berth congestion", c do
    order = %{trade("company:1") | limit: 0}
    s = ShipWorld.queue_trade(c.state, order)

    assert BerthAllocation.pending_status(
             s,
             c.account,
             Game.get(s, "ships", "company:1"),
             c.catalogue
           ) == :price_changed

    next = BerthAllocation.advance(s, c.catalogue)
    assert Game.get(next, "ships", "company:1")["status"] == "docked"
    refute Game.get(next, "ships", "company:1")["berth_granted_ms"]
  end

  test "a sale blocked by buyer funds resumes on recovery despite its retry timer", c do
    {:ok, s, _} =
      BerthAllocation.submit(c.state, c.account, %{trade("company:1") | quantity: 3}, c.catalogue)

    s = TijaraTides.Domain.Fleet.advance(%{s | clock_ms: 60_000}, 60_000)
    s = BerthAllocation.release_idle(s, c.catalogue)
    market = Game.get(s, "markets", "Jakarta|lumber")
    market = %{market | "buyer" => true, "demand" => 500, "budget" => 0}
    s = State.put(s, "markets", "Jakarta|lumber", market)
    order = %{trade("company:1") | side: "sell", limit: 0}
    s = ShipWorld.queue_trade(s, order)

    assert BerthAllocation.pending_status(
             s,
             c.account,
             Game.get(s, "ships", "company:1"),
             c.catalogue
           ) == :buyer_budget

    blocked = BerthAllocation.advance(s, c.catalogue)
    ship = Game.get(blocked, "ships", "company:1")
    assert ship["status"] == "docked"
    assert ship["berth_retry_ms"] > blocked.clock_ms
    assert ship["pending_quantity"] == 1

    recovered = State.put(blocked, "markets", "Jakarta|lumber", %{market | "budget" => 1_000_000})
    # Partial sales split lots, but read-only snapshots must not need database IDs.
    read_state = Map.put(recovered, :lot_allocation, [])
    projection = TijaraTides.UseCases.WorldProjection.build(read_state, c.catalogue)

    for _ <- 1..2 do
      view =
        TijaraTides.UseCases.GameQueries.snapshot(
          read_state,
          c.catalogue,
          projection,
          {:ok, c.account}
        )

      assert view.private["queued_trade_status"]["company:1"] == :berth_wait
      assert view.private["ships"]["company:1"]["pending_quantity"] == 1

      assert Enum.sum(Enum.map(view.private["ships"]["company:1"]["cargo"], & &1["quantity"])) ==
               3
    end

    assert read_state.lot_allocation == []
    filled = BerthAllocation.advance(recovered, c.catalogue)
    ship = Game.get(filled, "ships", "company:1")
    assert ship["status"] == "unloading"
    assert Enum.sum(Enum.map(ship["cargo"], & &1["quantity"])) == 2
    refute ship["pending_side"]
  end

  test "tankers must finish handling before placing another purchase", c do
    for status <- ["loading", "unloading"], good <- ["crude_oil", "refined_fuel"] do
      state =
        TijaraTides.Domain.BerthFixture.update(c.state, "company:1", %{
          class: "tanker",
          status: status,
          arrive_ms: 60_000
        })

      assert {:error, :tanker_purchase_handling} =
               BerthAllocation.submit(
                 state,
                 c.account,
                 %{trade("company:1") | good: good},
                 c.catalogue
               )

      refute Game.get(state, "ships", "company:1")["pending_side"]
    end

    state = TijaraTides.Domain.BerthFixture.update(c.state, "company:1", %{class: "tanker"})
    market = Game.get(state, "markets", "Jakarta|crude_oil")

    state =
      State.put(state, "markets", "Jakarta|crude_oil", %{market | "seller" => true, "stock" => 50})

    assert {:ok, next, result} =
             BerthAllocation.submit(
               state,
               c.account,
               %{trade("company:1") | good: "crude_oil"},
               c.catalogue
             )

    refute result["queued"]
    assert Game.get(next, "ships", "company:1")["status"] == "loading"
    market = Game.get(next, "markets", "Jakarta|crude_oil")

    next =
      State.put(next, "markets", "Jakarta|crude_oil", %{
        market
        | "buyer" => true,
          "demand" => 50,
          "budget" => 1_000_000
      })

    assert {:ok, _, %{"queued" => true}} =
             BerthAllocation.submit(
               next,
               c.account,
               %{trade("company:1") | good: "crude_oil", side: "sell", limit: 0},
               c.catalogue
             )
  end

  for status <- ["loading", "unloading"], side <- ["buy", "sell"] do
    test "queue #{side} while #{status}, safely cancel, then finish both operations before sailing",
         c do
      {:ok, initial, _} =
        BerthAllocation.submit(
          c.state,
          c.account,
          %{trade("company:1") | quantity: 3},
          c.catalogue
        )

      market = Game.get(initial, "markets", "Jakarta|lumber")

      initial =
        State.put(initial, "markets", "Jakarta|lumber", %{
          market
          | "buyer" => true,
            "demand" => 500,
            "budget" => 1_000_000
        })

      sale = %{trade("company:1") | side: "sell", limit: 0}

      initial =
        if unquote(status) == "unloading" do
          ship = Game.get(initial, "ships", "company:1")
          ready = TijaraTides.Domain.Fleet.advance(%{initial | clock_ms: ship["arrive_ms"]}, 0)
          {:ok, unloading, _} = BerthAllocation.submit(ready, c.account, sale, c.catalogue)
          unloading
        else
          initial
        end

      order = if unquote(side) == "buy", do: trade("company:1"), else: sale
      ship = Game.get(initial, "ships", "company:1")

      {:ok, queued, %{"queued" => true}} =
        BerthAllocation.submit(initial, c.account, order, c.catalogue)

      waiting = Game.get(queued, "ships", "company:1")

      for key <- ["status", "arrive_ms", "berth_granted_ms", "cargo"],
          do: assert(waiting[key] == ship[key])

      assert Game.get(queued, "companies", "company") == Game.get(initial, "companies", "company")
      assert BerthAllocation.pending_status(queued, c.account, waiting, c.catalogue) == :handling

      assert {:error, :berth_order_pending} =
               BerthAllocation.submit(queued, c.account, order, c.catalogue)

      {:ok, cancelled, _} = BerthAllocation.cancel(queued, c.account, "company:1")
      assert Game.get(cancelled, "ships", "company:1") == ship

      {:ok, planned, _} =
        ShipWorld.change_onward(
          queued,
          c.account,
          "company:1",
          "Jakarta",
          "Singapore",
          c.catalogue,
          true
        )

      still_handling = TijaraTides.Domain.ShipInstructions.advance(planned, c.catalogue)
      assert Game.get(still_handling, "ships", "company:1")["status"] == unquote(status)

      next =
        TijaraTides.Domain.Fleet.advance(%{still_handling | clock_ms: ship["arrive_ms"]}, 0)
        |> BerthAllocation.advance(c.catalogue)
        |> TijaraTides.Domain.ShipInstructions.advance(c.catalogue)

      handling = Game.get(next, "ships", "company:1")
      assert handling["status"] == if(unquote(side) == "buy", do: "loading", else: "unloading")
      refute handling["pending_side"]

      sailed =
        TijaraTides.Domain.Fleet.advance(%{next | clock_ms: handling["arrive_ms"]}, 0)
        |> TijaraTides.Domain.ShipInstructions.advance(c.catalogue)

      assert Game.get(sailed, "ships", "company:1")["status"] == "sailing"
      assert Game.get(sailed, "ships", "company:1")["destination"] == "Singapore"
    end
  end

  test "berth transitions reject releasing committed handling and duplicate pending trades", c do
    {:ok, handling, _} =
      BerthAllocation.submit(c.state, c.account, trade("company:1"), c.catalogue)

    assert_raise ArgumentError, fn -> ShipWorld.release_berth(handling, "company:1") end
    assert_raise ArgumentError, fn -> ShipWorld.grant_berth(handling, "company:1") end
    assert_raise ArgumentError, fn -> ShipWorld.cancel_pending_trade(c.state, "company:1") end
    queued = ShipWorld.queue_trade(c.state, trade("company:1"))
    assert_raise ArgumentError, fn -> ShipWorld.queue_trade(queued, trade("company:1")) end
    assert ShipWorld.request_berth(queued, "company:1") == queued
    cancelled = ShipWorld.cancel_pending_trade(queued, "company:1")
    refute Game.get(cancelled, "ships", "company:1")["berth_queued_ms"]
    refute Game.get(cancelled, "ships", "company:1")["pending_side"]
  end

  for admission <- [:immediate, :queued] do
    test "#{admission} trade retains berth through handling and releases when idle", c do
      before =
        if unquote(admission) == :queued,
          do:
            TijaraTides.Domain.BerthFixture.update(c.state, "company:1", %{berth_granted_ms: 0}),
          else: c.state

      {:ok, handling, _} =
        BerthAllocation.submit(before, c.account, trade("company:1"), c.catalogue)

      assert Game.get(handling, "ships", "company:1")["berth_granted_ms"] == 0
      queued = BerthAllocation.enqueue(handling, "company:2")
      finished = TijaraTides.Domain.Fleet.advance(%{queued | clock_ms: 1000}, 1000)
      assert Game.get(finished, "ships", "company:1")["berth_granted_ms"] == 0
      assert PortBerths.occupied?(Game.get(finished, "ships", "company:1"))
      # Subsequent work in this visit can use the original grant despite another ship waiting.
      {:ok, continuing, _} =
        BerthAllocation.submit(finished, c.account, trade("company:1"), c.catalogue)

      assert Game.get(continuing, "ships", "company:1")["berth_granted_ms"] == 0
      released = BerthAllocation.release_idle(finished, c.catalogue)
      refute PortBerths.occupied?(Game.get(released, "ships", "company:1"))
    end
  end

  test "finite handling capacity queues a manual order without settling and fills when released",
       c do
    {:ok, state, _} = BerthAllocation.submit(c.state, c.account, trade("company:1"), c.catalogue)
    cash = Game.get(state, "companies", "company")["cash"]

    {:ok, state, %{"queued" => true}} =
      BerthAllocation.submit(state, c.account, trade("company:2"), c.catalogue)

    assert Game.get(state, "companies", "company")["cash"] == cash
    assert Game.get(state, "ships", "company:2")["cargo"] == []

    assert PortBerths.position(PortBerthsWorld.load(state, "Jakarta", c.catalogue), "company:2") ==
             1

    assert {:error, :berth_order_pending} =
             BerthAllocation.submit(state, c.account, trade("company:2"), c.catalogue)

    state = Game.advance(state, 60_000, c.catalogue)
    assert Game.get(state, "ships", "company:2")["status"] == "loading"
    refute Game.get(state, "ships", "company:2")["pending_side"]
    assert length(Game.get(state, "ships", "company:2")["cargo"]) == 1
    assert Enum.count(PortBerthsWorld.ships(state, "Jakarta"), &PortBerths.occupied?/1) == 1
  end

  test "FIFO tickets survive repeated requests and invalid head does not block the next ship",
       c do
    state =
      c.state |> BerthAllocation.enqueue("company:2") |> BerthAllocation.enqueue("company:3")

    state =
      TijaraTides.Domain.BerthFixture.update(state, "company:2", %{
        pending_side: "buy",
        pending_good: "lumber",
        pending_quantity: 1,
        pending_limit: 0,
        pending_destination: "Singapore"
      })

    assert BerthAllocation.enqueue(state, "company:2") == state

    state =
      TijaraTides.Domain.BerthFixture.update(state, "company:3", %{
        pending_side: "buy",
        pending_good: "lumber",
        pending_quantity: 1,
        pending_limit: 1_000_000,
        pending_destination: "Singapore"
      })

    admitted = BerthAllocation.advance(state, c.catalogue)
    refute Game.get(admitted, "ships", "company:2")["berth_granted_ms"]
    assert Game.get(admitted, "ships", "company:2")["berth_retry_ms"] == 300_000
    assert Game.get(admitted, "ships", "company:3")["berth_granted_ms"] == 0
    released = BerthAllocation.release_idle(admitted, c.catalogue)
    assert Enum.count(PortBerthsWorld.ships(released, "Jakarta"), &PortBerths.occupied?/1) == 1
    assert BerthAllocation.enqueue(released, "company:2") == released
  end

  test "pending trades can only be cancelled by their owner", c do
    state =
      TijaraTides.Domain.BerthFixture.update(c.state, "company:1", %{
        pending_side: "buy",
        pending_good: "lumber",
        pending_quantity: 1,
        pending_limit: 1,
        pending_destination: "Singapore"
      })
      |> BerthAllocation.enqueue("company:1")

    assert {:error, :invalid_trade} =
             BerthAllocation.cancel(state, %{"company_id" => "other"}, "company:1")

    {:ok, next, _} = BerthAllocation.cancel(state, c.account, "company:1")
    refute Game.get(next, "ships", "company:1")["pending_side"]
    assert PortBerthsWorld.load(next, "Jakarta", c.catalogue).waiting == []

    # Without a queued trade there is nothing to cancel, and a berth the ship already
    # holds must not be revoked by the attempt.
    held = TijaraTides.Domain.BerthFixture.update(c.state, "company:1", %{berth_granted_ms: 0})
    assert {:error, :invalid_trade} = BerthAllocation.cancel(held, c.account, "company:1")

    # Cancelling gives up the ticket but must leave a cooldown standing, or submitting
    # and cancelling in a loop would evade the retry throttle entirely.
    cooling =
      TijaraTides.Domain.BerthFixture.update(state, "company:1", %{berth_retry_ms: 300_000})

    {:ok, cancelled, _} = BerthAllocation.cancel(cooling, c.account, "company:1")
    assert Game.get(cancelled, "ships", "company:1")["berth_retry_ms"] == 300_000
    assert BerthAllocation.enqueue(cancelled, "company:1") == cancelled
  end

  test "automatic instructions wait for a berth and stand aside for a queued manual trade", c do
    # Give Singapore stock to buy, so the order is blocked by the berth and nothing else.
    source = Game.get(c.state, "markets", "Jakarta|lumber")

    supplied =
      State.put(c.state, "markets", "Singapore|lumber", %{source | "port" => "Singapore"})

    {:ok, state, _} =
      TijaraTides.Domain.ShipInstructions.add(
        supplied,
        c.account,
        %{
          "ship" => "company:2",
          "port" => "Singapore",
          "side" => "buy",
          "good" => "lumber",
          "quantity" => 1,
          "limit" => 1_000_000,
          "budget" => 10_000_000,
          "onward" => "Jakarta"
        },
        %{id: "order", catalogue: c.catalogue}
      )

    quote = Game.voyage_quote(Game.get(state, "ships", "company:2"), "Singapore", c.catalogue)

    {:ok, state, _} =
      TijaraTides.Domain.Commands.execute(
        state,
        c.account,
        %{
          "action" => "sail",
          "ship" => "company:2",
          "destination" => "Singapore",
          "fuel_limit" => quote["fuel"]
        },
        %{catalogue: c.catalogue}
      )

    arrived = quote["duration_ms"]
    state = TijaraTides.Domain.Fleet.advance(%{state | clock_ms: arrived}, arrived)

    # Arriving takes a queue ticket, so the instruction cannot settle on admission.
    assert Game.get(state, "ships", "company:2")["berth_queued_ms"] == arrived
    waited = TijaraTides.Domain.Services.AutomatedVisits.advance(state, c.catalogue)
    assert Game.get(waited, "ship_instructions", "order")["status"] == "waiting"
    assert Game.get(waited, "ship_instructions", "order")["reason"] == "Waiting for a berth"
    assert Game.get(waited, "ships", "company:2")["cargo"] == []

    # Holding a berth, the same order settles — the control for the case below.
    admitted =
      TijaraTides.Domain.BerthFixture.update(state, "company:2", %{
        berth_queued_ms: nil,
        berth_granted_ms: arrived
      })

    filled = TijaraTides.Domain.Services.AutomatedVisits.advance(admitted, c.catalogue)
    assert Game.get(filled, "ships", "company:2")["cargo"] != []

    # A queued manual trade owns the ship until it settles or is cancelled, so an
    # automatic order must not slip a purchase in alongside it even holding a berth.
    pending =
      TijaraTides.Domain.BerthFixture.update(admitted, "company:2", %{
        pending_side: "buy",
        pending_good: "lumber",
        pending_quantity: 1,
        pending_limit: 1_000_000,
        pending_destination: "Jakarta"
      })

    skipped = TijaraTides.Domain.Services.AutomatedVisits.advance(pending, c.catalogue)
    assert Game.get(skipped, "ships", "company:2")["cargo"] == []
    assert Game.get(skipped, "ships", "company:2")["pending_side"] == "buy"
  end

  test "arrival joins automatically and waiting consumes no voyage fuel", c do
    ship = Game.get(c.state, "ships", "company:1")

    {:ok, state, _} =
      TijaraTides.Domain.Fleet.sail(
        c.state,
        c.account,
        ship["id"],
        "Singapore",
        100_000_000,
        c.catalogue
      )

    sailing = Game.get(state, "ships", ship["id"])
    now = sailing["arrive_ms"]
    state = TijaraTides.Domain.Fleet.advance(%{state | clock_ms: now}, now)
    arrived = Game.get(state, "ships", ship["id"])
    assert arrived["berth_queued_ms"] == now
    state = TijaraTides.Domain.Fleet.advance(%{state | clock_ms: now + 1000}, 1000)
    assert Game.get(state, "ships", ship["id"])["fuel_burned"] == arrived["fuel_burned"]
    assert Game.get(state, "ships", ship["id"])["berth_queued_ms"] == now
  end
end
