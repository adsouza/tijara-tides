defmodule TijaraTides.Infrastructure.TradeLimitsTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.Game
  alias TijaraTides.Infrastructure.{GameCatalogue, GameServer}

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
    maximum = GameServer.trade_limits(snapshot, ship, "Singapore")[{"buy", "Lumber"}]
    assert maximum > 0 and maximum < 500

    command = %{
      "action" => "buy",
      "ship" => ship["id"],
      "good" => "Lumber",
      "quantity" => maximum,
      "limit" => 100_000,
      "destination" => "Singapore"
    }

    assert {:ok, _, _} = Game.execute(state, account, command, %{}, catalogue)

    assert {:error, _} =
             Game.execute(state, account, %{command | "quantity" => maximum + 1}, %{}, catalogue)

    assert GameServer.trade_limits(snapshot, ship, nil)[{"buy", "Lumber"}] == 0

    reserved =
      put_in(snapshot.private["company"]["reserved"], snapshot.private["company"]["cash"])

    assert GameServer.trade_limits(reserved, ship, "Singapore")[{"buy", "Lumber"}] == 0
    unpaid = put_in(snapshot.private["company"]["unpaid"], 1)
    assert GameServer.trade_limits(unpaid, ship, "Singapore")[{"buy", "Lumber"}] == 0
    assert GameServer.trade_limits(snapshot, ship, "Singapore")[{"buy", "Crude oil"}] == 0
  end

  test "purchase caps respect both hold dimensions and stock" do
    {state, account, catalogue} = fixture()
    ship = Game.get(state, "ships", "company:1")

    state =
      Game.put(state, "companies", "company", %{
        Game.get(state, "companies", "company")
        | "cash" => 1_000_000_000
      })

    snapshot = view(state, account, catalogue)
    assert GameServer.trade_limits(snapshot, ship, "Singapore")[{"buy", "Lumber"}] == 500
    # Existing lumber leaves volume for only 62 more lots.
    loaded = %{ship | "cargo" => [%{"good" => "Lumber", "quantity" => 500}]}
    assert GameServer.trade_limits(snapshot, loaded, "Singapore")[{"buy", "Lumber"}] == 62
    heavy = %{ship | "cargo" => [%{"good" => "Iron ore", "quantity" => 499}]}
    assert GameServer.trade_limits(snapshot, heavy, "Singapore")[{"buy", "Lumber"}] == 2
    limited = put_in(snapshot.markets["Jakarta|Lumber"]["stock"], 3)
    assert GameServer.trade_limits(limited, ship, "Singapore")[{"buy", "Lumber"}] == 3
  end

  test "sales respect holdings, demand and buyer budget without requiring voyage funds" do
    {state, account, catalogue} = fixture()

    ship = %{
      Game.get(state, "ships", "company:1")
      | "port" => "Singapore",
        "cargo" => [%{"good" => "Lumber", "quantity" => 20}]
    }

    snapshot = view(state, account, catalogue)
    assert GameServer.trade_limits(snapshot, ship, nil)[{"sell", "Lumber"}] == 20
    limited = put_in(snapshot.markets["Singapore|Lumber"]["demand"], 7)
    assert GameServer.trade_limits(limited, ship, nil)[{"sell", "Lumber"}] == 7

    limited =
      put_in(
        limited.markets["Singapore|Lumber"]["buyer_budget"],
        2 * limited.markets["Singapore|Lumber"]["bid"]
      )

    assert GameServer.trade_limits(limited, ship, nil)[{"sell", "Lumber"}] == 2
    assert GameServer.trade_limits(limited, %{ship | "status" => "loading"}, nil) == %{}
  end
end
