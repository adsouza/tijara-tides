defmodule TijaraTides.Domain.TradeCommandTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{Commands, Game, State}
  alias TijaraTides.Domain.Services.BerthAllocation
  alias TijaraTides.UseCases.CommandPayload

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

  defp run(s, cat, command),
    do: Commands.execute(s, Game.get(s, "accounts", "a"), command, %{}, cat)

  defp quote(s, cat, good),
    do: TijaraTides.Domain.PortCargoMarketWorld.quote(s, cat, "Jakarta", good)

  defp buy(s, cat, fields \\ %{}) do
    Map.merge(
      %{
        "action" => "buy",
        "ship" => "aco:1",
        "good" => "lumber",
        "quantity" => 1,
        "limit" => quote(s, cat, "lumber")["ask"],
        "destination" => "Singapore"
      },
      fields
    )
  end

  # A good Jakarta buys, with 20 lots of it aboard the first ship.
  defp with_sellable_cargo(s, cat) do
    good =
      s.entities["markets"]
      |> Enum.filter(fn {key, m} ->
        g = String.replace_prefix(key, "Jakarta|", "")

        String.starts_with?(key, "Jakarta|") and m["buyer"] and m["demand"] > 20 and
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
    {State.put(s, "ships", "aco:1", %{ship | "cargo" => [batch]}), good}
  end

  test "malformed margin options are refused before any change", %{state: s, cat: cat} do
    for fields <- [
          %{"margin_bps" => -1},
          %{"margin_bps" => 1_001},
          %{"margin_bps" => 2.5},
          %{"margin_bps" => "200"},
          %{"margin_bps" => nil},
          %{"margin_bps" => 200, "save_margin" => "true"},
          %{"margin_bps" => 200, "save_margin" => 1},
          %{"margin_bps" => 200, "save_margin" => nil},
          %{"save_margin" => true}
        ] do
      assert run(s, cat, buy(s, cat, fields)) == {:error, :invalid_trade}, inspect(fields)
    end

    # An explicit false needs no margin; with one it is also well formed.
    assert {:ok, _, _} = run(s, cat, buy(s, cat, %{"save_margin" => false}))
    assert {:ok, _, _} = run(s, cat, buy(s, cat, %{"margin_bps" => 0, "save_margin" => false}))
  end

  test "integers beyond bigint keep their admission error", %{state: s, cat: cat} do
    assert CommandPayload.validate(buy(s, cat, %{"margin_bps" => 1_000_000_000_000_000_000_000})) ==
             {:error, :command_value_invalid}
  end

  test "a manual limit is admitted up to the player price ceiling", %{state: s, cat: cat} do
    assert {:ok, _, _} = run(s, cat, buy(s, cat, %{"limit" => 1_000_000_000_000}))

    assert run(s, cat, buy(s, cat, %{"limit" => 1_000_000_000_001})) ==
             {:error, :invalid_trade}

    sell = %{buy(s, cat) | "action" => "sell", "limit" => 1_000_000_000_001}
    assert run(s, cat, sell) == {:error, :invalid_trade}
  end

  test "a buy destination must be a catalogue port", %{state: s, cat: cat} do
    for destination <- ["Sing\u0000apore", "Atlantis", %{"port" => "Singapore"}, 7, nil] do
      assert run(s, cat, buy(s, cat, %{"destination" => destination})) ==
               {:error, :purchase_destination_required},
             inspect(destination)
    end
  end

  test "a queued sell never stores its client destination", %{state: s, cat: cat} do
    {s, good} = with_sellable_cargo(s, cat)
    s = BerthAllocation.enqueue(s, "aco:2")

    for destination <- ["A\u0000B", %{"x" => 1}, "Singapore"] do
      sell = %{
        "action" => "sell",
        "ship" => "aco:1",
        "good" => good,
        "quantity" => 5,
        "limit" => quote(s, cat, good)["bid"],
        "destination" => destination,
        "margin_bps" => 0
      }

      assert {:ok, next, %{"queued" => true}} = run(s, cat, sell)
      ship = Game.get(next, "ships", "aco:1")
      assert ship["pending_side"] == "sell"
      assert ship["pending_destination"] == nil
    end
  end

  test "a queued buy keeps its validated destination", %{state: s, cat: cat} do
    s = BerthAllocation.enqueue(s, "aco:2")
    assert {:ok, next, %{"queued" => true}} = run(s, cat, buy(s, cat, %{"margin_bps" => 0}))
    assert Game.get(next, "ships", "aco:1")["pending_destination"] == "Singapore"
  end
end
