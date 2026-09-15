defmodule Docs.BerthBoundaryTest do
  alias TijaraTides.Domain.PortBerthsWorld
  alias TijaraTides.Domain.ShipWorld
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{Game, PortBerths}
  alias TijaraTides.Domain.Services.BerthAllocation

  setup do
    catalogue =
      TijaraTides.Infrastructure.GameCatalogue.all()
      |> put_in(["ports", "Jakarta", "berth_count"], 1)

    state = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, catalogue)
    {:ok, state, _} = Game.seed_invite(state, "invite")
    {:ok, state, _} = Game.redeem(state, "invite", "session", %{id: "account", wall_ms: 0})

    {:ok, state, _} =
      TijaraTides.CompanyFixture.create_company(
        state,
        Game.get(state, "accounts", "account"),
        "Boundary Company",
        "Jakarta",
        "general",
        %{id: "company", catalogue: catalogue}
      )

    %{state: state, catalogue: catalogue}
  end

  # The value of routing berth writes through named transitions is that each one refuses
  # a state the aggregate forbids. Asserting that refusal tests the encapsulation itself,
  # where checking which functions exist or which calls appear in the source would pass
  # just as happily for a renamed function or a call written through an alias.
  test "named transitions refuse berth states the aggregate forbids", c do
    sailing = TijaraTides.Domain.BerthFixture.update(c.state, "company:1", %{status: "sailing"})

    assert_raise ArgumentError, fn -> ShipWorld.grant_berth(sailing, "company:1") end
    assert_raise ArgumentError, fn -> ShipWorld.release_berth(sailing, "company:1") end

    loading = TijaraTides.Domain.BerthFixture.update(c.state, "company:1", %{status: "loading"})
    assert_raise ArgumentError, fn -> ShipWorld.admit_handling(c.state, "company:1") end
    assert ShipWorld.admit_handling(loading, "company:1")

    # A cooldown must not be rewritten into the past, and a trade cannot be cancelled or
    # completed when there is none pending.
    assert_raise ArgumentError, fn -> ShipWorld.release_berth(c.state, "company:1", -1) end
    assert_raise ArgumentError, fn -> ShipWorld.cancel_pending_trade(c.state, "company:1") end
    assert_raise ArgumentError, fn -> ShipWorld.complete_pending_trade(c.state, "company:1") end
  end

  test "admission never seats more ships than the port has berths", c do
    state =
      Enum.reduce(["company:1", "company:2", "company:3"], c.state, fn id, acc ->
        ShipWorld.queue_trade(acc, %TijaraTides.Domain.Trade{
          ship_id: id,
          side: "buy",
          good: "lumber",
          quantity: 1,
          limit: 1_000_000,
          destination: "Singapore"
        })
      end)

    assert length(PortBerthsWorld.load(state, "Jakarta", c.catalogue).waiting) == 3

    admitted = BerthAllocation.advance(state, c.catalogue)
    model = PortBerthsWorld.load(admitted, "Jakarta", c.catalogue)

    # Jakarta has one berth, so at most one ship may hold it however many are waiting.
    assert model.held == MapSet.new(["company:1"])
    assert Enum.map(model.waiting, & &1["id"]) == ["company:2", "company:3"]
    assert Game.get(admitted, "ships", "company:1")["status"] == "loading"
    assert PortBerths.position(model, "company:2") == 1
    assert PortBerths.position(model, "company:3") == 2

    assert Enum.count(PortBerthsWorld.ships(admitted, "Jakarta"), &PortBerths.occupied?/1) <=
             model.capacity
  end
end
