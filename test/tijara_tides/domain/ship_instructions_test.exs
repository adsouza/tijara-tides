defmodule TijaraTides.Domain.ShipInstructionsTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{Game, State, ShipInstructions}

  def setup_game do
    catalogue = TijaraTides.Infrastructure.GameCatalogue.all()
    state = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, catalogue)
    {:ok, state, _} = Game.seed_invite(state, "invite")
    {:ok, state, _} = Game.redeem(state, "invite", "session", %{id: "account", wall_ms: 0})
    account = Game.get(state, "accounts", "account")
    ctx = %{id: "company", catalogue: catalogue}

    {:ok, state, _} =
      TijaraTides.CompanyFixture.execute(
        state,
        account,
        %{
          "action" => "company",
          "name" => "Ocean Company",
          "port" => "Jakarta",
          "package" => "general"
        },
        ctx,
        catalogue
      )

    {state, Game.get(state, "accounts", "account"), catalogue}
  end

  setup do
    {state, account, catalogue} = setup_game()
    # Use the real catalogue/quotes, with a small controllable supply at Singapore.
    source = Game.get(state, "markets", "Jakarta|lumber")
    market = %{source | "port" => "Singapore", "stock" => 2}
    state = State.put(state, "markets", "Singapore|lumber", market)
    %{state: state, account: account, catalogue: catalogue}
  end

  defp add(c, state, id, overrides \\ %{}) do
    params =
      Map.merge(
        %{
          "ship" => "company:1",
          "port" => "Singapore",
          "side" => "buy",
          "good" => "lumber",
          "quantity" => 3,
          "limit" => 1_000_000,
          "budget" => 10_000_000,
          "onward" => "Jakarta"
        },
        overrides
      )

    ShipInstructions.add(state, c.account, params, %{id: id, catalogue: c.catalogue})
  end

  defp arrive(c, state) do
    ship = Game.get(state, "ships", "company:1")
    quote = Game.voyage_quote(ship, "Singapore", c.catalogue)

    {:ok, state, _} =
      TijaraTides.Domain.Commands.execute(
        state,
        c.account,
        %{
          "action" => "sail",
          "ship" => ship["id"],
          "destination" => "Singapore",
          "fuel_limit" => quote["fuel"]
        },
        %{catalogue: c.catalogue}
      )

    # Isolate instruction execution from market replenishment.
    TijaraTides.Domain.Fleet.advance(
      %{state | clock_ms: quote["duration_ms"]},
      quote["duration_ms"]
    )
  end

  defp automatic(c, state, enabled \\ true) do
    {:ok, state, _} =
      ShipInstructions.change_onward(
        state,
        c.account,
        "company:1",
        "Singapore",
        "Jakarta",
        c.catalogue,
        enabled
      )

    state
  end

  test "automatic departure is opt-in, works empty, and reserves fuel only once", c do
    manual = automatic(c, c.state, false) |> then(&arrive(c, &1))
    assert ShipInstructions.advance(manual, c.catalogue) == manual
    enabled = automatic(c, manual)
    sailing = ShipInstructions.advance(enabled, c.catalogue)
    ship = Game.get(sailing, "ships", "company:1")
    assert ship["status"] == "sailing"
    assert ship["destination"] == "Jakarta"
    assert ship["cargo"] == []
    refute Game.get(sailing, "visit_plans", "company:1|Singapore")
    assert Game.get(sailing, "companies", "company")["reserved"] == ship["fuel_total"]
    assert ShipInstructions.advance(sailing, c.catalogue) == sailing

    assert Game.get(sailing, "notices", "auto-depart:company:1|Singapore")["text"] =~
             "automatically departed"
  end

  test "automatic departure waits through partial fills and handling, then sails", c do
    state = automatic(c, c.state)
    {:ok, state, _} = add(c, state, "order")
    assert Game.get(state, "visit_plans", "company:1|Singapore")["auto_depart"]
    state = arrive(c, state) |> ShipInstructions.advance(c.catalogue)
    assert Game.get(state, "ship_instructions", "order")["filled"] == 2
    assert Game.get(state, "ships", "company:1")["status"] == "loading"
    assert ShipInstructions.advance(state, c.catalogue) == state
    ship = Game.get(state, "ships", "company:1")

    waiting =
      TijaraTides.Domain.Fleet.advance(%{state | clock_ms: ship["arrive_ms"]}, 0)
      |> ShipInstructions.advance(c.catalogue)

    assert Game.get(waiting, "ships", "company:1")["status"] == "docked"
    assert Game.get(waiting, "visit_plans", "company:1|Singapore")["departure_wait"] =~ "orders"
    waiting = put_in(waiting, [:entities, "markets", "Singapore|lumber", "stock"], 5)
    loaded = ShipInstructions.advance(waiting, c.catalogue)
    assert Game.get(loaded, "ship_instructions", "order")["status"] == "filled"
    ship = Game.get(loaded, "ships", "company:1")
    assert ship["status"] == "loading"

    sailing =
      TijaraTides.Domain.Fleet.advance(%{loaded | clock_ms: ship["arrive_ms"]}, 0)
      |> ShipInstructions.advance(c.catalogue)

    assert Game.get(sailing, "ships", "company:1")["status"] == "sailing"
  end

  test "unfilled orders block automatic departure until cancelled; disabling retains manual control",
       c do
    {:ok, state, _} = add(c, automatic(c, c.state), "order", %{"limit" => 0})
    waiting = arrive(c, state) |> ShipInstructions.advance(c.catalogue)
    assert ShipInstructions.advance(waiting, c.catalogue) == waiting
    {:ok, cancelled, _} = ShipInstructions.cancel(waiting, c.account, "order", c.catalogue)
    disabled = automatic(c, cancelled, false)
    assert ShipInstructions.advance(disabled, c.catalogue) == disabled

    assert Game.get(ShipInstructions.advance(cancelled, c.catalogue), "ships", "company:1")[
             "status"
           ] == "sailing"
  end

  test "sell-only automatic visits wait for unloading to complete", c do
    c = %{c | state: put_in(c.state, [:entities, "markets", "Singapore|lumber", "demand"], 10)}
    c = %{c | state: put_in(c.state, [:entities, "markets", "Singapore|lumber", "buyer"], true)}
    {state, lot} = TijaraTides.Domain.CargoLots.create(c.state, "lumber", 1, nil)

    state =
      put_in(state, [:entities, "ships", "company:1", "cargo"], [
        Map.merge(lot, %{"good" => "lumber", "unit_cost" => 100})
      ])

    {:ok, state, _} =
      add(c, automatic(c, state), "sale", %{"side" => "sell", "quantity" => 1, "limit" => 0})

    unloading = arrive(c, state) |> ShipInstructions.advance(c.catalogue)
    ship = Game.get(unloading, "ships", "company:1")
    assert ship["status"] == "unloading"
    assert Game.get(unloading, "ship_instructions", "sale")["status"] == "filled"

    sailing =
      TijaraTides.Domain.Fleet.advance(%{unloading | clock_ms: ship["arrive_ms"]}, 0)
      |> ShipInstructions.advance(c.catalogue)

    assert Game.get(sailing, "ships", "company:1")["status"] == "sailing"
    assert Game.get(sailing, "ships", "company:1")["cargo"] == []
  end

  test "blocked automatic departure explains funding and retries after recovery", c do
    arrived = automatic(c, c.state) |> then(&arrive(c, &1))

    for {field, value, reason} <- [{"cash", 0, "funds"}, {"unpaid", 100, "unpaid"}] do
      blocked = put_in(arrived, [:entities, "companies", "company", field], value)

      blocked =
        if field == "unpaid",
          do:
            put_in(
              blocked,
              [:entities, "companies", "company", "reserved"],
              blocked.entities["companies"]["company"]["cash"]
            ),
          else: blocked

      waiting = ShipInstructions.advance(blocked, c.catalogue)
      assert Game.get(waiting, "ships", "company:1")["status"] == "docked"
      assert Game.get(waiting, "visit_plans", "company:1|Singapore")["departure_wait"] =~ reason
      assert Game.entities(waiting, "companies") == Game.entities(blocked, "companies")
      assert ShipInstructions.advance(waiting, c.catalogue) == waiting

      recovered =
        put_in(
          waiting,
          [:entities, "companies", "company", field],
          arrived.entities["companies"]["company"][field]
        )

      recovered =
        put_in(
          recovered,
          [:entities, "companies", "company", "reserved"],
          arrived.entities["companies"]["company"]["reserved"]
        )

      assert Game.get(ShipInstructions.advance(recovered, c.catalogue), "ships", "company:1")[
               "status"
             ] == "sailing"
    end
  end

  test "automatic departure rejects invalid settings and waits for unavailable routes", c do
    assert {:error, :instruction_auto_depart_invalid} =
             ShipInstructions.change_onward(
               c.state,
               c.account,
               "company:1",
               "Singapore",
               "Jakarta",
               c.catalogue,
               "yes"
             )

    arrived = automatic(c, c.state) |> then(&arrive(c, &1))
    missing = update_in(c.catalogue, ["routes"], &Map.delete(&1, "Singapore|Jakarta"))
    waiting = ShipInstructions.advance(arrived, missing)

    assert Game.get(waiting, "visit_plans", "company:1|Singapore")["departure_wait"] =~
             "No sea route"

    long = put_in(c.catalogue, ["routes", "Singapore|Jakarta", "nautical_miles"], 20_000_000)
    waiting = ShipInstructions.advance(arrived, long)

    assert Game.get(waiting, "visit_plans", "company:1|Singapore")["departure_wait"] =~
             "maximum duration"
  end

  test "arrival partially fills, handling prevents duplicate fills, retries finish the target",
       c do
    {:ok, state, _} = add(c, c.state, "order")
    assert ShipInstructions.advance(state, c.catalogue) == state
    state = arrive(c, state) |> ShipInstructions.advance(c.catalogue)
    assert Game.get(state, "ship_instructions", "order")["filled"] == 2
    assert Game.get(state, "ships", "company:1")["status"] == "loading"
    assert ShipInstructions.advance(state, c.catalogue) == state
    market = Game.get(state, "markets", "Singapore|lumber")
    state = State.put(state, "markets", "Singapore|lumber", %{market | "stock" => 5})
    ship = Game.get(state, "ships", "company:1")
    state = TijaraTides.Domain.Fleet.advance(%{state | clock_ms: ship["arrive_ms"]}, 0)
    state = ShipInstructions.advance(state, c.catalogue)
    assert Game.get(state, "ship_instructions", "order")["status"] == "filled"
    assert Game.get(state, "ship_instructions", "order")["filled"] == 3
    assert Game.get(state, "markets", "Singapore|lumber")["stock"] == 4
    assert ShipInstructions.advance(state, c.catalogue) == state
  end

  test "price and spending caps wait without moving cargo or cash; cancellation is private", c do
    {:ok, state, _} = add(c, c.state, "price", %{"limit" => 0})
    {:ok, state, _} = add(c, state, "budget", %{"budget" => 1})
    state = arrive(c, state)
    cash = Game.get(state, "companies", "company")["cash"]
    state = ShipInstructions.advance(state, c.catalogue)
    assert Game.get(state, "companies", "company")["cash"] == cash

    assert Game.get(state, "ship_instructions", "price")["reason"] ==
             "Waiting for the limit price"

    assert Game.get(state, "ship_instructions", "budget")["reason"] ==
             "Purchase spending cap exhausted"

    assert {:error, :instruction_not_active} =
             ShipInstructions.cancel(state, %{"company_id" => "other"}, "price", c.catalogue)

    assert Game.private(state, %{"id" => "other", "company_id" => "other"})["ship_instructions"] ==
             %{}

    refute Map.has_key?(Game.public(state, c.catalogue), "ship_instructions")
    {:ok, state, _} = ShipInstructions.cancel(state, c.account, "price", c.catalogue)
    state = ShipInstructions.advance(state, c.catalogue)
    assert Game.get(state, "ship_instructions", "price")["status"] == "cancelled"
  end

  test "departure cancels waiting remainders and mismatched plans", c do
    {:ok, state, _} = add(c, c.state, "order", %{"limit" => 0})
    state = arrive(c, state) |> ShipInstructions.advance(c.catalogue)
    ship = Game.get(state, "ships", "company:1")
    quote = Game.voyage_quote(ship, "Jakarta", c.catalogue)

    {:ok, state, _} =
      TijaraTides.Domain.Commands.execute(
        state,
        c.account,
        %{
          "action" => "sail",
          "ship" => ship["id"],
          "destination" => "Jakarta",
          "fuel_limit" => quote["fuel"]
        },
        %{catalogue: c.catalogue}
      )

    assert Game.get(state, "ship_instructions", "order")["status"] == "cancelled"
    {:ok, other, _} = add(c, c.state, "other")
    other = ShipInstructions.depart(other, "company:1", "Dubai", c.catalogue)
    assert Game.get(other, "ship_instructions", "other")["status"] == "cancelled"
  end

  test "sales settle and finish unloading before any purchase starts", c do
    {state, lot} = TijaraTides.Domain.CargoLots.create(c.state, "lumber", 1, nil)
    ship = Game.get(state, "ships", "company:1")
    cargo = [Map.merge(lot, %{"good" => "lumber", "unit_cost" => 100})]
    state = State.put(state, "ships", ship["id"], %{ship | "cargo" => cargo})
    market = Game.get(state, "markets", "Singapore|lumber")

    state =
      State.put(state, "markets", "Singapore|lumber", %{market | "buyer" => true, "demand" => 10})

    {:ok, state, _} = add(c, state, "a-buy", %{"quantity" => 1})
    {:ok, state, _} = add(c, state, "z-sell", %{"side" => "sell", "quantity" => 1, "limit" => 0})
    state = arrive(c, state) |> ShipInstructions.advance(c.catalogue)
    assert Game.get(state, "ship_instructions", "z-sell")["filled"] == 1
    assert Game.get(state, "ship_instructions", "a-buy")["filled"] == 0
    ship = Game.get(state, "ships", "company:1")
    assert ship["status"] == "unloading"
    state = TijaraTides.Domain.Fleet.advance(%{state | clock_ms: ship["arrive_ms"]}, 0)
    state = ShipInstructions.advance(state, c.catalogue)
    assert Game.get(state, "ship_instructions", "a-buy")["filled"] == 1
  end

  test "a full hold ends a loading shortfall only after sale targets are resolved", c do
    ship = Game.get(c.state, "ships", "company:1")
    class = TijaraTides.Domain.Fleet.classes()[ship["class"]]
    item = c.catalogue["goods"]["lumber"]
    lots = min(div(class["weight"], item["weight_kg"]), div(class["volume"], item["volume_l"]))
    {state, lot} = TijaraTides.Domain.CargoLots.create(c.state, "lumber", lots, nil)

    state =
      State.put(state, "ships", ship["id"], %{
        ship
        | "cargo" => [Map.merge(lot, %{"good" => "lumber", "unit_cost" => 100})]
      })

    {:ok, state, _} = add(c, state, "buy")
    state = arrive(c, state)
    automatic_wait = automatic(c, state) |> ShipInstructions.advance(c.catalogue)
    assert Game.get(automatic_wait, "ship_instructions", "buy")["status"] == "waiting"
    assert Game.get(automatic_wait, "ships", "company:1")["status"] == "docked"
    assert ShipInstructions.advance(automatic_wait, c.catalogue) == automatic_wait

    filled_hold = ShipInstructions.advance(state, c.catalogue)
    assert Game.get(filled_hold, "ship_instructions", "buy")["status"] == "cancelled"

    # A pending sale at this visit preserves the loading target until space can free.
    buy = Game.get(state, "ship_instructions", "buy")
    sale = %{buy | "id" => "sell", "side" => "sell", "limit" => 1_000_000}
    state = State.put(state, "ship_instructions", "sell", sale)
    state = ShipInstructions.advance(state, c.catalogue)
    assert Game.get(state, "ship_instructions", "buy")["status"] == "waiting"

    assert Game.get(state, "ship_instructions", "buy")["reason"] ==
             "Waiting for hold capacity; fill or cancel remaining orders"
  end

  for {fault, side, reason} <- [
        {:cargo, "sell", "Waiting for cargo aboard"},
        {:supply, "buy", "Waiting for market supply"},
        {:demand, "sell", "Waiting for market demand or buyer funds"},
        {:buyer_budget, "sell", "Waiting for market demand or buyer funds"},
        {:cash, "buy", "Waiting for available company funds or unpaid costs to clear"},
        {:reserved, "buy", "Waiting for available company funds or unpaid costs to clear"},
        {:unpaid, "buy", "Waiting for available company funds or unpaid costs to clear"},
        {:voyage_funds, "buy", "Waiting for funds after preserving onward voyage costs"},
        {:route, "buy", "Onward voyage is unavailable"},
        {:merchant, "buy", "Cargo is currently unavailable for trading at this port"}
      ] do
    @tag instruction_branch: fault
    test "waiting on #{fault} preserves settlement and resumes after the condition clears", c do
      fault = unquote(fault)

      state = c.state

      state =
        if unquote(side) == "sell" do
          {state, lot} = TijaraTides.Domain.CargoLots.create(state, "lumber", 1, nil)
          ship = Game.get(state, "ships", "company:1")

          state =
            State.put(state, "ships", ship["id"], %{
              ship
              | "cargo" => [Map.merge(lot, %{"good" => "lumber", "unit_cost" => 100})]
            })

          market = Game.get(state, "markets", "Singapore|lumber")

          State.put(state, "markets", "Singapore|lumber", %{
            market
            | "buyer" => true,
              "demand" => 10,
              "budget" => 1_000_000
          })
        else
          state
        end

      {:ok, state, _} =
        add(c, state, "order", %{
          "side" => unquote(side),
          "quantity" => 1,
          "limit" => if(unquote(side) == "sell", do: 0, else: 1_000_000)
        })

      state = arrive(c, state)

      {blocked, catalogue} = block_instruction(state, c.catalogue, fault)
      waiting = ShipInstructions.advance(blocked, catalogue)
      order = Game.get(waiting, "ship_instructions", "order")
      assert order["status"] == "waiting"
      assert order["reason"] == unquote(reason)
      assert order["filled"] == 0

      for kind <- ["companies", "ships", "markets"] do
        assert Game.entities(waiting, kind) == Game.entities(blocked, kind)
      end

      for key <- [:journal, :new_lots, :next_lot_id],
          do: assert(Map.get(waiting, key) == Map.get(blocked, key))

      # Repeated ticks do not settle or emit duplicate notices while blocked.
      assert ShipInstructions.advance(waiting, catalogue) == waiting
      # Restore only the external resources, retaining the waiting instruction.
      resumed =
        Enum.reduce(["companies", "ships", "markets"], waiting, fn kind, acc ->
          put_in(acc, [:entities, kind], Game.entities(state, kind))
        end)
        |> ShipInstructions.advance(c.catalogue)

      assert Game.get(resumed, "ship_instructions", "order")["filled"] == 1
      assert Game.get(resumed, "ship_instructions", "order")["status"] == "filled"
      assert ShipInstructions.advance(resumed, c.catalogue) == resumed
    end
  end

  defp block_instruction(state, catalogue, fault) do
    ship = Game.get(state, "ships", "company:1")
    company = Game.get(state, "companies", "company")
    market = Game.get(state, "markets", "Singapore|lumber")

    case fault do
      :cargo ->
        {State.put(state, "ships", ship["id"], %{ship | "cargo" => []}), catalogue}

      :supply ->
        {State.put(state, "markets", "Singapore|lumber", %{market | "stock" => 0}), catalogue}

      :demand ->
        {State.put(state, "markets", "Singapore|lumber", %{market | "demand" => 0}), catalogue}

      :buyer_budget ->
        {State.put(state, "markets", "Singapore|lumber", %{market | "budget" => 0}), catalogue}

      :cash ->
        {State.put(state, "companies", "company", %{company | "cash" => 0}), catalogue}

      :reserved ->
        {State.put(state, "companies", "company", %{company | "reserved" => company["cash"]}),
         catalogue}

      :unpaid ->
        {State.put(state, "companies", "company", %{
           company
           | "unpaid" => 1,
             "cash" => 0,
             "reserved" => 0
         }), catalogue}

      :voyage_funds ->
        cost =
          TijaraTides.Domain.Trading.purchase_total(
            Game.quote(state, catalogue, "Singapore", "lumber"),
            ship,
            catalogue["goods"]["lumber"],
            1
          )

        {State.put(state, "companies", "company", %{company | "cash" => cost, "reserved" => 0}),
         catalogue}

      :route ->
        {state, update_in(catalogue, ["routes"], &Map.delete(&1, "Singapore|Jakarta"))}

      :merchant ->
        {State.put(state, "markets", "Singapore|lumber", %{market | "merchant" => true}),
         catalogue}
    end
  end

  for {field, value, error} <- [
        {"ship", "missing", :instruction_ship_not_owned},
        {"port", "missing", :instruction_destination_invalid},
        {"side", "other", :instruction_cargo_invalid},
        {"good", "missing", :instruction_cargo_invalid},
        {"good", "crude_oil", :instruction_cargo_invalid},
        {"quantity", "1", :instruction_quantity_invalid},
        {"quantity", 10_001, :instruction_quantity_invalid},
        {"limit", "100", :instruction_quantity_invalid},
        {"limit", -1, :instruction_quantity_invalid},
        {"limit", 1_000_000_000_001, :instruction_quantity_invalid},
        {"budget", nil, :instruction_budget_invalid},
        {"budget", 0, :instruction_budget_invalid},
        {"budget", 1_000_000_000_001, :instruction_budget_invalid},
        {"onward", "missing", :instruction_budget_invalid}
      ] do
    test "rejects #{field}=#{inspect(value)} without creating an instruction", c do
      assert {:error, unquote(error)} =
               add(c, c.state, "bad", %{unquote(field) => unquote(value)})

      assert Game.entities(c.state, "ship_instructions") == %{}
    end
  end

  test "twenty active instructions is a cap, and cancellation releases a slot", c do
    state =
      Enum.reduce(1..20, c.state, fn n, state ->
        {:ok, state, _} = add(c, state, "order-#{n}")
        state
      end)

    assert {:error, :instruction_limit_reached} = add(c, state, "overflow")
    {:ok, state, _} = ShipInstructions.cancel(state, c.account, "order-1", c.catalogue)

    assert {:error, :instruction_not_active} =
             ShipInstructions.cancel(state, c.account, "order-1", c.catalogue)

    assert {:error, :instruction_not_active} =
             ShipInstructions.cancel(state, c.account, "missing", c.catalogue)

    assert {:ok, _, _} = add(c, state, "replacement")
  end

  test "a sailing ship accepts only its destination and unavailable markets are rejected", c do
    ship = Game.get(c.state, "ships", "company:1")

    state =
      State.put(c.state, "ships", ship["id"], %{
        ship
        | "status" => "sailing",
          "destination" => "Singapore"
      })

    assert {:ok, _, _} = add(c, state, "valid")
    assert {:error, :instruction_destination_invalid} = add(c, state, "bad", %{"port" => "Dubai"})
    state = State.delete(state, "markets", "Singapore|lumber")
    assert {:error, :instruction_cargo_invalid} = add(c, state, "missing-market")
    catalogue = put_in(c.catalogue, ["goods", "lumber", "manual"], false)

    assert {:error, :instruction_cargo_invalid} =
             add(%{c | catalogue: catalogue}, c.state, "auction-only")
  end

  test "one onward port per visit, with an atomic owner-only change", c do
    {:ok, state, _} = add(c, c.state, "first")
    {:ok, state, _} = add(c, state, "second")

    assert {:error, :instruction_onward_conflict} =
             add(c, state, "conflict", %{"onward" => "Dubai"})

    assert {:error, :instruction_ship_not_owned} =
             ShipInstructions.change_onward(
               state,
               %{"company_id" => "other"},
               "company:1",
               "Singapore",
               "Dubai",
               c.catalogue
             )

    assert {:error, :instruction_onward_invalid} =
             ShipInstructions.change_onward(
               state,
               c.account,
               "company:1",
               "Singapore",
               "Singapore",
               c.catalogue
             )

    assert {:error, :instruction_destination_invalid} =
             ShipInstructions.change_onward(
               state,
               c.account,
               "company:1",
               "missing",
               "Singapore",
               c.catalogue
             )

    {:ok, changed, _} =
      ShipInstructions.change_onward(
        state,
        c.account,
        "company:1",
        "Singapore",
        "Dubai",
        c.catalogue
      )

    for id <- ["first", "second"],
        do: assert(Game.get(changed, "ship_instructions", id)["onward"] == "Dubai")

    for kind <- ["companies", "ships", "markets"],
        do: assert(Game.entities(changed, kind) == Game.entities(state, kind))

    assert {:ok, _, _} = add(c, changed, "third", %{"onward" => "Dubai"})
    assert {:ok, _, _} = add(c, changed, "other-ship", %{"ship" => "company:2"})
  end

  test "legacy conflicting instructions pause before any purchase until explicitly resolved", c do
    {:ok, state, _} = add(c, c.state, "first")
    {:ok, state, _} = add(c, state, "second")
    state = put_in(state, [:entities, "ship_instructions", "second", "onward"], "Dubai")
    state = arrive(c, state)
    waiting = ShipInstructions.advance(state, c.catalogue)

    for id <- ["first", "second"] do
      order = Game.get(waiting, "ship_instructions", id)
      assert order["filled"] == 0
      assert order["reason"] =~ "shared onward port"
    end

    assert Game.entities(waiting, "companies") == Game.entities(state, "companies")
    assert Game.entities(waiting, "ships") == Game.entities(state, "ships")

    {:ok, fixed, _} =
      ShipInstructions.change_onward(
        waiting,
        c.account,
        "company:1",
        "Singapore",
        "Jakarta",
        c.catalogue
      )

    filled = ShipInstructions.advance(fixed, c.catalogue)
    assert Game.get(filled, "ship_instructions", "first")["filled"] == 2
  end

  test "an empty or sell-only visit has an independent private onward plan", c do
    {:ok, planned, _} =
      ShipInstructions.change_onward(
        c.state,
        c.account,
        "company:1",
        "Singapore",
        "Jakarta",
        c.catalogue
      )

    assert Game.entities(planned, "ship_instructions") == %{}
    assert Game.get(planned, "visit_plans", "company:1|Singapore")["onward"] == "Jakarta"
    assert Game.entities(planned, "companies") == Game.entities(c.state, "companies")
    assert Game.entities(planned, "ships") == Game.entities(c.state, "ships")
    refute Map.has_key?(Game.public(planned, c.catalogue), "visit_plans")

    assert Game.private(planned, %{"id" => "other", "company_id" => "other"})["visit_plans"] ==
             %{}

    arrived = arrive(c, planned)
    assert Game.get(arrived, "visit_plans", "company:1|Singapore")
    assert Game.get(arrived, "ships", "company:1")["cargo"] == []

    assert Game.get(
             ShipInstructions.depart(arrived, "company:1", "Jakarta", c.catalogue),
             "visit_plans",
             "company:1|Singapore"
           ) == nil

    {planned, lot} = TijaraTides.Domain.CargoLots.create(planned, "lumber", 1, nil)
    ship = Game.get(planned, "ships", "company:1")

    planned =
      State.put(planned, "ships", ship["id"], %{
        ship
        | "cargo" => [Map.merge(lot, %{"good" => "lumber", "unit_cost" => 100})]
      })

    {:ok, sell_only, _} = add(c, planned, "sell", %{"side" => "sell", "quantity" => 1})

    {:ok, changed, _} =
      ShipInstructions.change_onward(
        sell_only,
        c.account,
        "company:1",
        "Singapore",
        "Dubai",
        c.catalogue
      )

    assert Game.get(changed, "ship_instructions", "sell")["onward"] == nil
    assert Game.get(changed, "visit_plans", "company:1|Singapore")["onward"] == "Dubai"
  end

  test "sell targets cannot exceed the total currently aboard", c do
    assert {:error, :instruction_sell_exceeds_cargo} =
             add(c, c.state, "empty", %{"side" => "sell", "quantity" => 1})

    ship = Game.get(c.state, "ships", "company:1")
    {state, first} = TijaraTides.Domain.CargoLots.create(c.state, "lumber", 2, nil)
    {state, second} = TijaraTides.Domain.CargoLots.create(state, "lumber", 3, nil)
    cargo = Enum.map([first, second], &Map.merge(&1, %{"good" => "lumber", "unit_cost" => 100}))
    state = State.put(state, "ships", ship["id"], %{ship | "cargo" => cargo})
    assert {:ok, _, _} = add(c, state, "exact", %{"side" => "sell", "quantity" => 5})

    assert {:error, :instruction_sell_exceeds_cargo} =
             add(c, state, "too-many", %{"side" => "sell", "quantity" => 6})
  end

  test "reject invalid ownership, quantities, cargo and onward destinations", c do
    assert {:error, :instruction_destination_invalid} =
             add(c, c.state, "bad", %{"port" => "Jakarta"})

    assert {:error, :instruction_quantity_invalid} = add(c, c.state, "bad", %{"quantity" => 0})

    assert {:error, :instruction_budget_invalid} =
             add(c, c.state, "bad", %{"onward" => "Singapore"})

    assert {:error, :instruction_ship_not_owned} =
             add(%{c | account: %{"company_id" => "other"}}, c.state, "bad")
  end
end
