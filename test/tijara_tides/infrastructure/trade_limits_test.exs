defmodule TijaraTides.Infrastructure.TradeLimitsTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.Game
  alias TijaraTides.Infrastructure.{GameCatalogue, GameServer}

  test "cargo menu filtering follows ship class, including loaded tankers and refrigerated dry holds" do
    {state, account, catalogue} = fixture()
    definitions = %{catalogue: catalogue}
    snapshot = view(state, account, catalogue)
    query = TijaraTides.UseCases.GameQueries
    all = query.cargo_options(definitions, snapshot, false)
    assert all == query.cargo_options(definitions, snapshot, false, nil)
    assert {"crude_oil", _} = List.keyfind(all, "crude_oil", 0)

    for {class, allowed} <- [
          {"freighter", ["dry"]},
          {"reefer", ["dry", "reefer"]},
          {"tanker", ["liquid"]}
        ] do
      ship = %{"class" => class, "cargo" => [%{"good" => "crude_oil", "quantity" => 1}]}
      filtered = query.cargo_options(definitions, snapshot, false, ship)
      expected = Enum.filter(all, fn {good, _} -> catalogue["goods"][good]["hold"] in allowed end)
      assert filtered == expected
      assert filtered != []
      sorted = query.cargo_options(definitions, snapshot, true, ship)
      assert Map.new(sorted) == Map.new(filtered)
    end

    tanker = %{"class" => "tanker", "cargo" => [%{"good" => "crude_oil"}]}

    assert {"vegetable_oil", _} =
             List.keyfind(
               query.cargo_options(definitions, snapshot, false, tanker),
               "vegetable_oil",
               0
             )

    assert query.cargo_options(definitions, %{snapshot | markets: %{}}, false, tanker) == []
  end

  test "sell instruction quantities sum cargo batches and clamp when cargo or side changes" do
    {state, _account, catalogue} = fixture()
    ship = Game.get(state, "ships", "company:1")

    ship = %{
      ship
      | "cargo" => [
          %{"good" => "lumber", "quantity" => 2},
          %{"good" => "lumber", "quantity" => 3},
          %{"good" => "appliances", "quantity" => 1}
        ]
    }

    editor = &TijaraTides.UseCases.GameQueries.instruction_editor(%{catalogue: catalogue}, &1, &2)
    draft = %{"side" => "sell", "good" => "lumber", "quantity" => "99"}
    assert %{maximum: 5, quantity: 5, good: "lumber"} = editor.(ship, draft)
    assert %{maximum: 1, quantity: 1} = editor.(ship, %{draft | "good" => "appliances"})
    assert %{maximum: 0, quantity: 0} = editor.(%{ship | "cargo" => []}, draft)
    assert %{maximum: 10_000, quantity: 99} = editor.(ship, %{draft | "side" => "buy"})
    assert %{quantity: 1} = editor.(ship, %{draft | "quantity" => ""})
  end

  defp fixture do
    catalogue = GameCatalogue.all()
    state = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, catalogue)
    {:ok, state, _} = Game.seed_invite(state, "invite")
    {:ok, state, _} = Game.redeem(state, "invite", "session", %{id: "account", wall_ms: 0})
    account = Game.get(state, "accounts", "account")

    {:ok, state, _} =
      Game.execute(
        state,
        account,
        %{"action" => "company", "name" => "Limits", "port" => "Jakarta", "package" => "general"},
        %{id: "company", catalogue: catalogue},
        catalogue
      )

    {state, Game.get(state, "accounts", "account"), catalogue}
  end

  defp view(state, account, catalogue) do
    %{
      private: Game.private(state, account),
      public: %{"clock_ms" => state.clock_ms},
      markets:
        Map.new(Game.entities(state, "markets"), fn {id, market} ->
          {id, Game.quote(state, catalogue, market["port"], market["good"])}
        end)
    }
  end

  test "largest purchase settles, while one extra lot cannot meet voyage funding" do
    {state, account, catalogue} = fixture()
    ship = Game.get(state, "ships", "company:1")
    snapshot = view(state, account, catalogue)
    maximum = GameServer.trade_limits(snapshot, ship, "Singapore")[{"buy", "lumber"}]
    assert maximum > 0 and maximum < 500

    command = %{
      "action" => "buy",
      "ship" => ship["id"],
      "good" => "lumber",
      "quantity" => maximum,
      "limit" => 100_000,
      "destination" => "Singapore"
    }

    assert {:ok, _, _} = Game.execute(state, account, command, %{}, catalogue)

    assert {:error, _} =
             Game.execute(state, account, %{command | "quantity" => maximum + 1}, %{}, catalogue)

    assert GameServer.trade_limits(snapshot, ship, nil)[{"buy", "lumber"}] == 0

    reserved =
      put_in(snapshot.private["company"]["reserved"], snapshot.private["company"]["cash"])

    assert GameServer.trade_limits(reserved, ship, "Singapore")[{"buy", "lumber"}] == 0
    unpaid = put_in(snapshot.private["company"]["unpaid"], 1)
    assert GameServer.trade_limits(unpaid, ship, "Singapore")[{"buy", "lumber"}] == 0
    assert GameServer.trade_limits(snapshot, ship, "Singapore")[{"buy", "crude_oil"}] == 0
  end

  test "purchase caps respect both hold dimensions and stock" do
    {state, account, catalogue} = fixture()
    ship = Game.get(state, "ships", "company:1")

    state =
      TijaraTides.Domain.State.put(state, "companies", "company", %{
        Game.get(state, "companies", "company")
        | "cash" => 1_000_000_000
      })

    snapshot = view(state, account, catalogue)
    assert GameServer.trade_limits(snapshot, ship, "Singapore")[{"buy", "lumber"}] == 500
    # Existing lumber leaves volume for only 62 more lots.
    loaded = %{ship | "cargo" => [%{"good" => "lumber", "quantity" => 500}]}
    assert GameServer.trade_limits(snapshot, loaded, "Singapore")[{"buy", "lumber"}] == 62
    heavy = %{ship | "cargo" => [%{"good" => "iron_ore", "quantity" => 499}]}
    assert GameServer.trade_limits(snapshot, heavy, "Singapore")[{"buy", "lumber"}] == 2
    limited = put_in(snapshot.markets["Jakarta|lumber"]["stock"], 3)
    assert GameServer.trade_limits(limited, ship, "Singapore")[{"buy", "lumber"}] == 3
  end

  test "sales respect holdings, demand and buyer budget without requiring voyage funds" do
    {state, account, catalogue} = fixture()

    ship = %{
      Game.get(state, "ships", "company:1")
      | "port" => "Singapore",
        "cargo" => [%{"good" => "lumber", "quantity" => 20}]
    }

    snapshot = view(state, account, catalogue)
    assert GameServer.trade_limits(snapshot, ship, nil)[{"sell", "lumber"}] == 20
    limited = put_in(snapshot.markets["Singapore|lumber"]["demand"], 7)
    assert GameServer.trade_limits(limited, ship, nil)[{"sell", "lumber"}] == 7

    limited =
      put_in(
        limited.markets["Singapore|lumber"]["buyer_budget"],
        2 * limited.markets["Singapore|lumber"]["bid"]
      )

    assert GameServer.trade_limits(limited, ship, nil)[{"sell", "lumber"}] == 2
    assert GameServer.trade_limits(limited, %{ship | "status" => "loading"}, nil) == %{}
  end
end
