defmodule TijaraTides.Domain.PortBerthsTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{Game, Ship, State, Trade, PortBerths}
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

  for admission <- [:immediate, :queued] do
    test "#{admission} trade retains berth through handling and releases when idle", c do
      before =
        if unquote(admission) == :queued,
          do: Ship.update_berth(c.state, "company:1", %{berth_granted_ms: 0}),
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
    assert PortBerths.position(state, Game.get(state, "ships", "company:2")) == 1

    assert {:error, :berth_order_pending} =
             BerthAllocation.submit(state, c.account, trade("company:2"), c.catalogue)

    state = Game.advance(state, 60_000, c.catalogue)
    assert Game.get(state, "ships", "company:2")["status"] == "loading"
    refute Game.get(state, "ships", "company:2")["pending_side"]
    assert length(Game.get(state, "ships", "company:2")["cargo"]) == 1
    assert Enum.count(PortBerths.ships(state, "Jakarta"), &PortBerths.occupied?/1) == 1
  end

  test "FIFO tickets survive repeated requests and invalid head does not block the next ship",
       c do
    state =
      c.state |> BerthAllocation.enqueue("company:2") |> BerthAllocation.enqueue("company:3")

    state =
      Ship.update_berth(state, "company:2", %{
        pending_side: "buy",
        pending_good: "lumber",
        pending_quantity: 1,
        pending_limit: 0,
        pending_destination: "Singapore"
      })

    assert BerthAllocation.enqueue(state, "company:2") == state

    state =
      Ship.update_berth(state, "company:3", %{
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
    assert Enum.count(PortBerths.ships(released, "Jakarta"), &PortBerths.occupied?/1) == 1
    assert BerthAllocation.enqueue(released, "company:2") == released
  end

  test "pending trades can only be cancelled by their owner", c do
    state =
      Ship.update_berth(c.state, "company:1", %{
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
    assert PortBerths.queue(next, "Jakarta") == []

    # Without a queued trade there is nothing to cancel, and a berth the ship already
    # holds must not be revoked by the attempt.
    held = Ship.update_berth(c.state, "company:1", %{berth_granted_ms: 0})
    assert {:error, :invalid_trade} = BerthAllocation.cancel(held, c.account, "company:1")
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
      Ship.update_berth(state, "company:2", %{berth_queued_ms: nil, berth_granted_ms: arrived})

    filled = TijaraTides.Domain.Services.AutomatedVisits.advance(admitted, c.catalogue)
    assert Game.get(filled, "ships", "company:2")["cargo"] != []

    # A queued manual trade owns the ship until it settles or is cancelled, so an
    # automatic order must not slip a purchase in alongside it even holding a berth.
    pending =
      Ship.update_berth(admitted, "company:2", %{
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
