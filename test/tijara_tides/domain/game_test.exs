defmodule TijaraTides.Domain.GameTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.Game
  alias TijaraTides.Infrastructure.GameCatalogue

  def setup_game do
    catalogue = GameCatalogue.all()
    state = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, catalogue)
    {:ok, state, _} = Game.seed_invite(state, "invite")
    {:ok, state, _} = Game.redeem(state, "invite", "session", %{id: "account", wall_ms: 0})
    account = Game.get(state, "accounts", "account")
    ctx = %{id: "company", catalogue: catalogue}

    {:ok, state, _} =
      Game.execute(
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

  test "redemption retries cannot revive expired sessions or overwrite another account" do
    {state, _account, _catalogue} = setup_game()

    assert {:replay, %{"account_id" => "account"}} =
             Game.redeem(state, "invite", "session", %{id: "unused", wall_ms: 1})

    assert {:error, :invalid_invitation} =
             Game.redeem(state, "invite", "session", %{id: "unused", wall_ms: 365 * 86_400_000})

    {:ok, state, _} = Game.seed_invite(state, "second")

    assert {:error, :invalid_invitation} =
             Game.redeem(state, "second", "session", %{id: "unused", wall_ms: 1})
  end

  test "departure failures identify status, destination, budget, arrears and available funds" do
    {state, account, catalogue} = setup_game()
    ship = Game.get(state, "ships", "company:1")
    company = Game.get(state, "companies", "company")
    estimate = Game.voyage_quote(ship, "Singapore", catalogue)

    command = %{
      "action" => "sail",
      "ship" => ship["id"],
      "destination" => "Singapore",
      "fuel_limit" => estimate["fuel"]
    }

    run = fn state, command, catalogue ->
      Game.execute(state, account, command, %{}, catalogue)
    end

    assert {:error, :departure_ship_unavailable} =
             run.(state, %{command | "ship" => "missing"}, catalogue)

    foreign =
      TijaraTides.Domain.State.put(state, "ships", ship["id"], %{ship | "company_id" => "other"})

    assert {:error, :departure_ship_unavailable} = run.(foreign, command, catalogue)

    for status <- ["loading", "unloading", "sailing"] do
      busy =
        TijaraTides.Domain.State.put(state, "ships", ship["id"], %{
          ship
          | "status" => status,
            "arrive_ms" => 5000
        })

      assert {:error, {:departure_busy, ^status, 5000}} = run.(busy, command, catalogue)
    end

    assert {:error, :departure_destination_invalid} =
             run.(state, %{command | "destination" => nil}, catalogue)

    assert {:error, {:departure_already_here, "Jakarta"}} =
             run.(state, %{command | "destination" => "Jakarta"}, catalogue)

    assert {:error, {:departure_no_route, "Jakarta", "Singapore"}} =
             run.(state, command, Map.put(catalogue, "routes", %{}))

    assert {:error, :departure_fuel_limit_invalid} =
             run.(state, %{command | "fuel_limit" => nil}, catalogue)

    fuel = estimate["fuel"]

    assert {:error, {:departure_fuel_limit, ^fuel, 0}} =
             run.(state, %{command | "fuel_limit" => 0}, catalogue)

    unpaid =
      TijaraTides.Domain.State.put(state, "companies", "company", %{
        company
        | "unpaid" => 1250,
          "cash" => 0,
          "reserved" => 0
      })

    assert {:error, {:departure_unpaid, 1250}} = run.(unpaid, command, catalogue)

    poor =
      TijaraTides.Domain.State.put(state, "companies", "company", %{
        company
        | "cash" => 500,
          "reserved" => 400
      })

    assert {:error, {:departure_funds, ^fuel, 0, 100}} = run.(poor, command, catalogue)
    canal = put_in(catalogue, ["routes", "Jakarta|Singapore", "passages"], ["suez"])
    assert {:error, {:departure_funds, ^fuel, 25_000, 100}} = run.(poor, command, canal)

    long = put_in(catalogue, ["routes", "Jakarta|Singapore", "nautical_miles"], 20_000_000)

    assert {:error, {:departure_too_long, duration}} =
             run.(state, %{command | "fuel_limit" => 9_999_999_999}, long)

    assert duration > 86_400_000
  end

  test "catalogue production IDs and aluminium display name stay consistent" do
    catalogue = GameCatalogue.all()
    assert Enum.all?(Game.raw_goods(), &Map.has_key?(catalogue["goods"], &1))
    assert catalogue["goods"]["aluminium_scrap"]["name"] == "Aluminium scrap"
    broken = update_in(catalogue, ["goods"], &Map.delete(&1, "aluminium_scrap"))

    assert_raise ArgumentError, ~r/unknown raw production good/, fn ->
      Game.initialize(%{entities: %{}, clock_ms: 0}, broken)
    end
  end

  test "unknown role goods are rejected before shelf life or merchant checks" do
    for role <- ["++exp", "++exp/++imp"] do
      catalogue =
        put_in(GameCatalogue.all(), ["ports", "Jakarta", "roles", "Unknown cargo"], role)

      assert_raise ArgumentError, "unknown role good at Jakarta: Unknown cargo", fn ->
        Game.initialize(%{entities: %{}, clock_ms: 0}, catalogue)
      end
    end
  end

  test "cargo identifiers are independent of labels and malformed catalogue identities fail early" do
    catalogue = GameCatalogue.all()
    renamed = put_in(catalogue, ["goods", "aluminium_scrap", "name"], "Recycled aluminium")
    state = Game.initialize(%{entities: %{}, clock_ms: 0}, renamed)
    assert Game.get(state, "markets", "Jakarta|aluminium_scrap")["good"] == "aluminium_scrap"

    for {field, value} <- [{"id", "Aluminium scrap"}, {"name", ""}, {"name", nil}] do
      broken = put_in(catalogue, ["goods", "aluminium_scrap", field], value)

      assert_raise ArgumentError, ~r/cargo requires a machine ID and display name/, fn ->
        Game.initialize(%{entities: %{}, clock_ms: 0}, broken)
      end
    end
  end

  test "perishable merchant roles are rejected before world creation" do
    catalogue = put_in(GameCatalogue.all(), ["ports", "Jakarta", "roles", "fruit"], "exp/imp")

    assert_raise ArgumentError, ~r/perishable merchant/, fn ->
      Game.initialize(%{entities: %{}, clock_ms: 0}, catalogue)
    end
  end

  test "orphan ships fail explicitly instead of silently dropping operating costs" do
    {state, account, catalogue} = setup_game()

    assert_raise ArgumentError, ~r/retire or transfer ships/, fn ->
      TijaraTides.Domain.State.delete(state, "companies", account["company_id"])
    end

    state = %{state | entities: Map.put(state.entities, "companies", %{})}

    assert_raise ArgumentError, ~r/retire or transfer ships/, fn ->
      Game.advance(state, 1000, catalogue)
    end
  end

  test "initialization bounds notices per account and keeps the newest ones" do
    {state, account, catalogue} = setup_game()

    notices =
      Map.new(1..150, fn n ->
        {Integer.to_string(n),
         %{"account_id" => account["id"], "clock_ms" => n, "text" => "notice"}}
      end)

    state = %{state | entities: Map.put(state.entities, "notices", notices)}
    state = Game.initialize(state, catalogue)
    private = Game.private(state, account)
    assert length(private["notices"]) == 100
    assert hd(private["notices"])["clock_ms"] == 150
    assert List.last(private["notices"])["clock_ms"] == 51
  end

  test "purchase totals include handling and the applicable tanker cleaning fee" do
    goods = GameCatalogue.all()["goods"]
    quote = %{"ask" => 1000, "handling_fee" => 200}
    ship = %{"class" => "tanker", "last_liquid" => "crude_oil"}
    assert Game.purchase_total(quote, ship, goods["crude_oil"], 3) == 3600
    assert Game.purchase_total(quote, ship, goods["refined_fuel"], 3) == 8600
    assert Game.purchase_total(quote, ship, goods["vegetable_oil"], 3) == 28600
    assert Game.purchase_total(quote, ship, goods["vegetable_oil"], 0) == 0
  end

  test "cargo compatibility shares hold and single-liquid rules" do
    goods = GameCatalogue.all()["goods"]
    ship = fn class -> %{"class" => class, "cargo" => []} end
    assert Game.compatible_cargo?(ship.("freighter"), goods["lumber"])
    refute Game.compatible_cargo?(ship.("freighter"), goods["fruit"])
    refute Game.compatible_cargo?(ship.("freighter"), goods["crude_oil"])
    assert Game.compatible_cargo?(ship.("reefer"), goods["fruit"])
    assert Game.compatible_cargo?(ship.("reefer"), goods["lumber"])
    assert Game.compatible_cargo?(ship.("tanker"), goods["vegetable_oil"])
    refute Game.compatible_cargo?(ship.("tanker"), goods["lumber"])
    loaded = Map.put(ship.("tanker"), "cargo", [%{"good" => "crude_oil", "quantity" => 1}])
    assert Game.compatible_cargo?(loaded, goods["crude_oil"])
    refute Game.compatible_cargo?(loaded, goods["vegetable_oil"])
  end

  test "freshness estimates use purchased batches, selected quantity and full unloading time" do
    batches = [
      %{"good" => "fruit", "quantity" => 2, "expires_ms" => 10_000},
      %{"good" => "fruit", "quantity" => 3, "expires_ms" => 20_000}
    ]

    assert Game.freshness(batches, 2, 1000, Game.handling_ms(2))["after_ms"] == 8000
    assert Game.freshness(batches, 5, 1000, Game.handling_ms(5))["after_ms"] == 6500
    assert Game.freshness(batches, 5, 9000, Game.handling_ms(5))["after_ms"] == 0

    assert [%{"good" => "fruit", "quantity" => 5, "arrival_ms" => 4000, "unloaded_ms" => 1500}] =
             Game.voyage_freshness(%{"cargo" => batches}, 1000, 5000)

    assert Game.voyage_freshness(
             %{"cargo" => [%{"good" => "lumber", "quantity" => 1, "expires_ms" => nil}]},
             0,
             5000
           ) == []
  end

  test "starter packages contain three ships and equal total capital" do
    for {package, fleet} <- Game.packages() do
      assert length(fleet) == 3
      assert Game.package_cash(package) > 0

      assert Game.package_cash(package) + Enum.sum(Enum.map(fleet, &Game.classes()[&1]["price"])) ==
               20_000_000
    end
  end

  test "company formation replaces its pending invitation notice, including after reload" do
    {state, account, catalogue} = setup_game()

    state =
      Enum.reduce(["child", "other"], state, fn id, state ->
        {:ok, state, _} =
          Game.execute(state, account, %{"action" => "invite"}, %{invite_hash: id}, catalogue)

        {:ok, state, _} = Game.redeem(state, id, id <> "-session", %{id: id, wall_ms: 0})
        state
      end)

    pending = Game.get(state, "notices", "accepted:child")
    assert pending["text"] == "Your invitation was accepted. Company formation is pending."

    {:ok, state, _} =
      Game.execute(
        state,
        Game.get(state, "accounts", "child"),
        %{
          "action" => "company",
          "name" => "Tygre Trafficking",
          "port" => "Jakarta",
          "package" => "general"
        },
        %{id: "child-company", catalogue: catalogue},
        catalogue
      )

    assert Game.get(state, "notices", "accepted:child") == nil

    assert Game.get(state, "notices", "company:child-company")["text"] ==
             "Your invitee now runs Tygre Trafficking."

    assert Game.get(state, "notices", "accepted:other") != nil
    assert length(state.notices_by_account["account"]) == 2

    # Older saves can contain both stages of the same invitation.
    state = put_in(state.entities["notices"]["accepted:child"], pending)
    reloaded = Game.initialize(state, catalogue)
    assert Game.get(reloaded, "notices", "accepted:child") == nil
    assert length(reloaded.notices_by_account["account"]) == 2
  end

  test "invitation redemption and expiry cannot both consume and refund quota" do
    {state, account, catalogue} = setup_game()

    {:ok, state, result} =
      Game.execute(state, account, %{"action" => "invite"}, %{invite_hash: "child"}, catalogue)

    assert Game.get(state, "accounts", "account")["invite_quota"] == 2

    {:ok, redeemed, _} =
      Game.redeem(state, "child", "other-session", %{id: "child-account", wall_ms: 0})

    assert {:error, :invalid_invitation} =
             Game.redeem(redeemed, "child", "third", %{id: "third", wall_ms: 0})

    redeemed = Game.advance(redeemed, result["expires_ms"], catalogue)
    assert Game.get(redeemed, "accounts", "account")["invite_quota"] == 2
    expired = Game.advance(state, result["expires_ms"], catalogue)
    assert Game.get(expired, "accounts", "account")["invite_quota"] == 3
    expired = Game.advance(expired, 1, catalogue)
    assert Game.get(expired, "accounts", "account")["invite_quota"] == 3

    assert {:error, :invalid_invitation} =
             Game.redeem(expired, "child", "other", %{id: "other", wall_ms: 0})
  end

  test "purchases require a route and preserve loaded voyage costs plus fleet upkeep" do
    {state, account, catalogue} = setup_game()
    ship = Game.get(state, "ships", "company:1")
    company = Game.get(state, "companies", "company")
    item = catalogue["goods"]["lumber"]

    state =
      TijaraTides.Domain.State.put(state, "companies", company["id"], %{
        company
        | "cash" => 100_000_000
      })

    fleet = Game.entities(state, "ships") |> Map.values()

    command = %{
      "action" => "buy",
      "ship" => ship["id"],
      "good" => "lumber",
      "quantity" => 500,
      "limit" => 100_000
    }

    for destination <- [nil, "Jakarta", "unknown", %{}] do
      assert {:error, :purchase_destination_required} =
               Game.execute(
                 state,
                 account,
                 Map.put(command, "destination", destination),
                 %{},
                 catalogue
               )
    end

    command = Map.put(command, "destination", "Singapore")
    voyage = Game.purchase_voyage(ship, item, 500, "Singapore", fleet, state.clock_ms, catalogue)
    assert voyage["fuel"] > Game.voyage_quote(ship, "Singapore", catalogue)["fuel"]
    assert voyage["upkeep"] > voyage["crew_estimate"]

    total =
      Game.purchase_total(Game.quote(state, catalogue, "Jakarta", "lumber"), ship, item, 500)

    required = voyage["required"]

    state =
      TijaraTides.Domain.State.put(state, "companies", company["id"], %{
        company
        | "cash" => total + required - 1
      })

    assert {:error, {:purchase_voyage_funds, "Singapore", ^required, remaining}} =
             Game.execute(state, account, command, %{}, catalogue)

    assert remaining == required - 1

    state =
      TijaraTides.Domain.State.put(state, "companies", company["id"], %{
        company
        | "cash" => total + required
      })

    assert {:ok, bought, _} = Game.execute(state, account, command, %{}, catalogue)
    bought = Game.advance(bought, Game.handling_ms(500), catalogue)

    assert {:ok, sailing, _} =
             Game.execute(
               bought,
               account,
               %{
                 "action" => "sail",
                 "ship" => ship["id"],
                 "destination" => "Singapore",
                 "fuel_limit" => voyage["fuel"]
               },
               %{},
               catalogue
             )

    arrived = Game.advance(sailing, voyage["duration_ms"], catalogue)
    assert Game.get(arrived, "companies", company["id"])["unpaid"] == 0
    assert Game.get(arrived, "ships", ship["id"])["port"] == "Singapore"
  end

  test "buying reserves actual capacity and cannot bypass ownership, funds, limits or handling" do
    {state, account, catalogue} = setup_game()

    buy = %{
      "action" => "buy",
      "destination" => "Singapore",
      "ship" => "company:1",
      "good" => "lumber",
      "quantity" => 10,
      "limit" => 30_000
    }

    {:ok, after_buy, _} = Game.execute(state, account, buy, %{}, catalogue)
    assert Game.get(after_buy, "ships", "company:1")["status"] == "loading"
    assert Game.get(after_buy, "markets", "Jakarta|lumber")["stock"] == 490
    assert {:error, :invalid_trade} = Game.execute(after_buy, account, buy, %{}, catalogue)

    assert {:error, :invalid_trade} =
             Game.execute(state, %{account | "company_id" => "other"}, buy, %{}, catalogue)

    assert {:error, :price_changed} =
             Game.execute(state, account, %{buy | "limit" => 1}, %{}, catalogue)

    assert {:error, :capacity_exceeded} =
             Game.execute(state, account, %{buy | "quantity" => 1000}, %{}, catalogue)

    assert {:error, :invalid_trade} =
             Game.execute(state, account, %{buy | "quantity" => -1}, %{}, catalogue)
  end

  test "voyage arrives, reserved fuel is spent once, and other players cannot inspect cargo" do
    {state, account, catalogue} = setup_game()

    {:ok, state, _} =
      Game.execute(
        state,
        account,
        %{
          "action" => "buy",
          "destination" => "Singapore",
          "ship" => "company:1",
          "good" => "lumber",
          "quantity" => 10,
          "limit" => 30_000
        },
        %{},
        catalogue
      )

    state = Game.advance(state, 5000, catalogue)
    ship = Game.get(state, "ships", "company:1")
    estimate = Game.voyage_quote(ship, "Singapore", catalogue)

    {:ok, state, _} =
      Game.execute(
        state,
        account,
        %{
          "action" => "sail",
          "ship" => "company:1",
          "destination" => "Singapore",
          "fuel_limit" => estimate["fuel"]
        },
        %{},
        catalogue
      )

    assert Game.get(state, "companies", "company")["reserved"] == estimate["fuel"]
    public = Game.public(state, catalogue)
    refute Map.has_key?(public["ships"]["company:1"], "cargo")
    refute Map.has_key?(public["companies"]["company"], "cash")
    assert Game.private(state, %{"id" => "stranger", "company_id" => "other"})["ships"] == %{}
    arrived = Game.advance(state, estimate["duration_ms"], catalogue)
    assert Game.get(arrived, "ships", "company:1")["port"] == "Singapore"
    assert Game.get(arrived, "companies", "company")["reserved"] == 0
    again = Game.advance(arrived, 0, catalogue)
    assert again == arrived

    assert {:ok, sold, _} =
             Game.execute(
               arrived,
               account,
               %{
                 "action" => "sell",
                 "ship" => "company:1",
                 "good" => "lumber",
                 "quantity" => 10,
                 "limit" => 1
               },
               %{},
               catalogue
             )

    assert Game.get(sold, "ships", "company:1")["cargo"] == []
  end

  test "legacy voyages accelerate once while preserving progress and fuel already spent" do
    {state, account, catalogue} = setup_game()

    {:ok, state, _} =
      Game.execute(
        state,
        account,
        %{
          "action" => "sail",
          "ship" => "company:1",
          "destination" => "Singapore",
          "fuel_limit" => 100_000_000
        },
        %{id: "sail", catalogue: catalogue},
        catalogue
      )

    ship = Game.get(state, "ships", "company:1")
    burned = div(ship["fuel_total"], 2)

    legacy =
      ship
      |> Map.delete("voyage_speedup")
      |> Map.merge(%{
        "depart_ms" => 0,
        "arrive_ms" => 100_000,
        "last_cost_ms" => 50_000,
        "fuel_burned" => burned
      })

    state = put_in(state, [:entities, "ships", "company:1"], legacy)
    state = %{state | clock_ms: 50_000}
    migrated = Game.advance(state, 0, catalogue)
    ship = Game.get(migrated, "ships", "company:1")
    assert ship["depart_ms"] == 45_000
    assert ship["arrive_ms"] == 55_000
    assert ship["fuel_burned"] == burned
    assert ship["voyage_speedup"] == 600
    again = Game.advance(migrated, 0, catalogue)
    assert Game.get(again, "ships", "company:1") == ship

    assert Game.get(Game.advance(again, 5_000, catalogue), "ships", "company:1")["status"] ==
             "docked"
  end

  test "all starter ship routes fit the voyage ceiling and the shortest fit idle time" do
    catalogue = GameCatalogue.all()

    for {class, _} <- Game.classes() do
      times =
        for {_, port} <- catalogue["ports"],
            destination <- Map.keys(catalogue["ports"]),
            destination != port["id"] do
          Game.voyage_quote(
            %{"class" => class, "port" => port["id"], "cargo" => []},
            destination,
            catalogue
          )["duration_ms"]
        end

      assert Enum.max(times) <= 8_640_000
      assert Enum.min(times) < 30_000
    end
  end

  test "perishable purchases retain source freshness and spoilage writes off cargo once" do
    {state, account, catalogue} = setup_game()
    state = Game.advance(state, 60_000, catalogue)
    ship = Game.get(state, "ships", "company:1") |> Map.put("class", "reefer")
    state = TijaraTides.Domain.State.put(state, "ships", ship["id"], ship)
    expiry = hd(Game.get(state, "markets", "Jakarta|fruit")["batches"])["expires_ms"]

    command = %{
      "action" => "buy",
      "destination" => "Singapore",
      "ship" => ship["id"],
      "good" => "fruit",
      "quantity" => 2,
      "limit" => 100_000
    }

    assert {:ok, bought, _} = Game.execute(state, account, command, %{}, catalogue)
    assert hd(Game.get(bought, "ships", ship["id"])["cargo"])["expires_ms"] == expiry
    expired = Game.advance(bought, expiry - bought.clock_ms, catalogue)
    assert Game.get(expired, "ships", ship["id"])["cargo"] == []
    assert Game.advance(expired, 0, catalogue) == expired
  end

  test "market recovery is one lot per 150 seconds and preserves partial intervals" do
    {state, _account, catalogue} = setup_game()
    supplier = Game.get(state, "markets", "Jakarta|lumber")
    buyer = Game.get(state, "markets", "Singapore|lumber")

    state =
      state
      |> TijaraTides.Domain.State.put("markets", "Jakarta|lumber", %{supplier | "stock" => 490})
      |> TijaraTides.Domain.State.put("markets", "Singapore|lumber", %{
        buyer
        | "demand" => 490,
          "budget" => 0
      })

    before = Enum.reduce(1..29, state, fn _, acc -> Game.advance(acc, 5_000, catalogue) end)
    assert Game.get(before, "markets", "Jakarta|lumber")["stock"] == 490
    assert Game.get(before, "markets", "Singapore|lumber")["demand"] == 490
    after_tick = Game.advance(before, 5_000, catalogue)
    assert Game.get(after_tick, "markets", "Jakarta|lumber")["stock"] == 491
    assert Game.get(after_tick, "markets", "Singapore|lumber")["demand"] == 491

    assert Game.get(after_tick, "markets", "Singapore|lumber")["budget"] ==
             catalogue["goods"]["lumber"]["reference_cents"]

    ten_minutes = Game.advance(after_tick, 450_000, catalogue)
    assert Game.get(ten_minutes, "markets", "Jakarta|lumber")["stock"] == 494
    assert Game.get(ten_minutes, "markets", "Singapore|lumber")["demand"] == 494
    capped = Game.advance(ten_minutes, 86_400_000, catalogue)
    assert Game.get(capped, "markets", "Jakarta|lumber")["stock"] == 500
    assert Game.get(capped, "markets", "Singapore|lumber")["demand"] == 500
  end

  test "market freshness expires between production boundaries" do
    {state, _, catalogue} = setup_game()
    market = Game.get(state, "markets", "Jakarta|fruit")
    market = %{market | "batches" => [%{"quantity" => 500, "expires_ms" => 1}]}
    state = TijaraTides.Domain.State.put(state, "markets", "Jakarta|fruit", market)
    state = Game.advance(state, 1, catalogue)
    assert Game.get(state, "markets", "Jakarta|fruit")["stock"] == 0
    assert Game.quote(state, catalogue, "Jakarta", "fruit")["stock"] == 0
  end

  test "device expiry and invalid credentials never expose an account" do
    {state, _, _} = setup_game()
    assert {:ok, _} = Game.authenticate(state, "session", 0)
    assert {:error, :invalid_session} = Game.authenticate(state, "session", 365 * 86_400_000)
    assert {:error, :invalid_session} = Game.authenticate(state, "unknown", 0)
  end
end
