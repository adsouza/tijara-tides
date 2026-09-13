defmodule TijaraTides.Domain.ReroutingTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{Game, Fleet, State, VoyageNavigation}

  setup do
    catalogue = TijaraTides.Infrastructure.GameCatalogue.all()
    state = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, catalogue)
    {:ok, state, _} = Game.seed_invite(state, "invite")
    {:ok, state, _} = Game.redeem(state, "invite", "session", %{id: "account", wall_ms: 0})

    {:ok, state, _} =
      TijaraTides.CompanyFixture.create_company(
        state,
        Game.get(state, "accounts", "account"),
        "Diversions",
        "Jakarta",
        "general",
        %{id: "company", catalogue: catalogue}
      )

    account = Game.get(state, "accounts", "account")
    {:ok, state, _} = Fleet.sail(state, account, "company:1", "Singapore", 1_000_000, catalogue)
    duration = Game.get(state, "ships", "company:1")["arrive_ms"]
    state = Game.advance(state, div(duration, 10), catalogue)
    %{state: state, account: account, catalogue: catalogue}
  end

  test "turning back releases fuel and retains the current position and spent fuel", c do
    old = Game.get(c.state, "ships", "company:1")
    {point, _, _, _} = VoyageNavigation.split(old, c.state.clock_ms, c.catalogue)
    quote = Fleet.reroute_quote(old, "Jakarta", c.state.clock_ms, c.catalogue)
    assert quote["released_fuel"] > 0
    cash = Game.get(c.state, "companies", "company")["cash"]
    reserved = Game.get(c.state, "companies", "company")["reserved"]

    {:ok, state, _} =
      Fleet.reroute(c.state, c.account, old["id"], "Jakarta", quote["fuel"], c.catalogue)

    ship = Game.get(state, "ships", old["id"])
    assert hd(ship["voyage_path"]) == point
    assert ship["destination"] == "Jakarta"
    assert ship["cargo"] == old["cargo"]
    assert Game.get(state, "companies", "company")["cash"] == cash

    assert Game.get(state, "companies", "company")["reserved"] ==
             reserved - quote["released_fuel"]

    assert old["fuel_burned"] > 0
    state = Game.advance(state, div(quote["duration_ms"], 2), c.catalogue)
    ship = Game.get(state, "ships", old["id"])
    {point, _, _, _} = VoyageNavigation.split(ship, state.clock_ms, c.catalogue)
    next = Fleet.reroute_quote(ship, "Colombo", state.clock_ms, c.catalogue)

    {:ok, state, _} =
      Fleet.reroute(state, c.account, ship["id"], "Colombo", next["fuel"], c.catalogue)

    assert hd(Game.get(state, "ships", ship["id"])["voyage_path"]) == point
    state = Game.advance(state, next["duration_ms"], c.catalogue)
    assert Game.get(state, "ships", ship["id"])["port"] == "Colombo"
    assert Game.get(state, "companies", "company")["reserved"] == 0
  end

  test "diversion pauses a running route without moving or cancelling port instructions", c do
    route = %{
      "id" => "company:1",
      "ship_id" => "company:1",
      "company_id" => "company",
      "status" => "running",
      "cursor" => 0,
      "visit" => 1,
      "phase" => "arrival",
      "auto_depart" => true,
      "stop_after" => false,
      "reason" => "Following route"
    }

    order = %{
      "id" => "order",
      "ship_id" => "company:1",
      "company_id" => "company",
      "port" => "Singapore",
      "status" => "planned"
    }

    state =
      c.state
      |> State.put("ship_routes", "company:1", route)
      |> State.put("ship_instructions", "order", order)

    {:ok, changed, _} =
      Fleet.reroute(state, c.account, "company:1", "Jakarta", 1_000_000, c.catalogue)

    assert Game.get(changed, "ship_routes", "company:1")["status"] == "paused"
    assert Game.get(changed, "ship_instructions", "order") == order
  end

  test "unfunded and unauthorized diversions leave the original voyage intact", c do
    company = Game.get(c.state, "companies", "company")
    state = State.put(c.state, "companies", "company", %{company | "cash" => company["reserved"]})

    assert {:error, :reroute_funds} =
             Fleet.reroute(state, c.account, "company:1", "Colombo", 9_000_000, c.catalogue)

    assert {:error, :reroute_invalid} =
             Fleet.reroute(
               c.state,
               %{"company_id" => "other"},
               "company:1",
               "Colombo",
               9_000_000,
               c.catalogue
             )

    assert {:error, :reroute_invalid} =
             Fleet.reroute(c.state, c.account, "company:1", "Singapore", 9_000_000, c.catalogue)

    assert {:error, :reroute_invalid} =
             Fleet.reroute(c.state, c.account, "company:1", "Colombo", 0, c.catalogue)
  end

  test "reroute geometry follows known edges and canal tolls already paid are retained", c do
    ship = Game.get(c.state, "ships", "company:1")
    quote = Fleet.reroute_quote(ship, "Rotterdam", c.state.clock_ms, c.catalogue)
    assert "suez" in quote["route"]["passages"]
    assert quote["canal_fees"] == 25_000
    paid = Map.put(ship, "paid_canals", 2)

    assert Fleet.reroute_quote(paid, "Rotterdam", c.state.clock_ms, c.catalogue)["canal_fees"] ==
             0

    edges =
      for {_, r} <- c.catalogue["routes"],
          [a, b] <- Enum.chunk_every(r["coordinates"], 2, 1, :discard),
          into: MapSet.new(),
          do: {VoyageNavigation.normalize(a), VoyageNavigation.normalize(b)}

    for [a, b] <- Enum.chunk_every(tl(quote["route"]["coordinates"]), 2, 1, :discard) do
      assert MapSet.member?(edges, {a, b}) or MapSet.member?(edges, {b, a})
    end
  end
end
