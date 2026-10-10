defmodule TijaraTides.UseCases.ShipyardOffersTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{AccountWorld, Fleet, Game, Journal}
  alias TijaraTides.Domain.Services.{CompanyFormation, Credit}
  alias TijaraTides.UseCases.GameQueries

  # Independent approved matrix: catches a generator edit that both command
  # and query would otherwise agree on, including accidental provisional sales.
  @expected %{
    "Shanghai" => ~w(small_freighter freighter bulk tanker),
    "Busan" => ~w(small_freighter freighter bulk tanker),
    "Tokyo" => ~w(bulk),
    "Hong Kong" => [],
    "Shenzhen" => [],
    "Guangzhou" => ~w(small_freighter freighter bulk reefer tanker),
    "Singapore" => [],
    "Ho Chi Minh City" => ~w(small_freighter freighter),
    "Jakarta" => [],
    "Manila" => ~w(tanker),
    "Colombo" => ~w(small_freighter freighter bulk),
    "Mumbai" => ~w(small_freighter freighter),
    "Dubai" => [],
    "Abu Dhabi" => ~w(small_freighter freighter),
    "Rotterdam" => ~w(small_freighter freighter),
    "Antwerp" => [],
    "Hamburg" => [],
    "Valencia" => [],
    "Athens" => [],
    "Tangier" => [],
    "New York City" => [],
    "Los Angeles" => [],
    "Houston" => [],
    "Colón" => [],
    "São Paulo" => []
  }

  setup do
    definitions = TijaraTides.UseCases.Game.definitions()
    catalogue = definitions.catalogue
    state = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, catalogue)
    {:ok, state, _} = AccountWorld.seed_invite(state, "invite")
    {:ok, state, _} = AccountWorld.redeem(state, "invite", "session", %{id: "a", wall_ms: 0})

    {:ok, state, _} =
      CompanyFormation.create_company(state, Game.get(state, "accounts", "a"), "Buyer", %{
        id: "co",
        catalogue: catalogue
      })

    account = Game.get(state, "accounts", "a")
    {:ok, state, _} = Credit.borrow(state, account, 10_000_000, "loan")
    %{definitions: definitions, state: Journal.clear(state), account: account}
  end

  test "all 25 ports offer exactly the approved classes and every offer is executable", c do
    assert Enum.sort(Map.keys(c.definitions.catalogue["ports"])) == Enum.sort(Map.keys(@expected))
    assert map_size(@expected) == 25

    for {port, expected} <- @expected do
      offered = GameQueries.shipyard(c.definitions, port).classes
      assert Enum.sort(Map.keys(offered)) == Enum.sort(expected), port

      for {class, spec} <- c.definitions.classes do
        context = %{id: "new-hull", catalogue: c.definitions.catalogue}
        result = Fleet.purchase(c.state, c.account, class, port, spec["price"], context)

        if class in expected do
          assert {:ok, bought, %{"ship_id" => "new-hull", "spent" => price}} = result
          assert price == offered[class]["price"]
          assert Game.get(bought, "ships", "new-hull")["port"] == port
          assert Game.get(bought, "ships", "new-hull")["class"] == class
          assert Game.get(bought, "companies", "co")["cash"] == 10_000_000 - price
          assert [%{entries: [{"fleet", ^price}, {"cash_available", negative}]}] = bought.journal
          assert negative == -price

          assert {:error, :ship_price_changed} =
                   Fleet.purchase(c.state, c.account, class, port, price - 1, context)
        else
          assert result == {:error, :ship_class_unavailable}, "#{port}: #{class}"
        end
      end
    end
  end

  test "regional labels identify exactly the three approved off-port yards", c do
    regions = %{
      "Tokyo" => "Tokyo Bay (Yokohama)",
      "Manila" => "Manila Bay (Mariveles)",
      "Rotterdam" => "Rhine–Meuse delta (Hardinxveld and Aalst)"
    }

    for port <- Map.keys(@expected) do
      assert GameQueries.shipyard(c.definitions, port).region == regions[port]
    end
  end

  test "first-ship ports include only executable yards, ranked by class count", c do
    ports = GameQueries.shipyard_ports(c.definitions)

    assert Enum.map(ports, & &1.port) == [
             "Guangzhou",
             "Busan",
             "Shanghai",
             "Colombo",
             "Abu Dhabi",
             "Ho Chi Minh City",
             "Mumbai",
             "Rotterdam",
             "Manila",
             "Tokyo"
           ]

    for yard <- ports do
      assert yard.classes == GameQueries.shipyard(c.definitions, yard.port).classes
      assert map_size(yard.classes) > 0
    end

    definitions =
      put_in(c.definitions, [:catalogue, "ports", "Guangzhou", "shipyard", "classes"], [])

    refute Enum.any?(GameQueries.shipyard_ports(definitions), &(&1.port == "Guangzhou"))
  end

  test "catalogue changes feed query and command together; missing metadata fails closed", c do
    definitions =
      put_in(c.definitions, [:catalogue, "ports", "Guangzhou", "shipyard", "classes"], ["bulk"])

    assert Map.keys(GameQueries.shipyard(definitions, "Guangzhou").classes) == ["bulk"]
    context = %{id: "new-hull", catalogue: definitions.catalogue}

    assert {:error, :ship_class_unavailable} =
             Fleet.purchase(c.state, c.account, "reefer", "Guangzhou", 5_000_000, context)

    assert GameQueries.shipyard(c.definitions, "missing") == %{classes: %{}, region: nil}
    assert Fleet.shipyard_classes(%{"ports" => %{"legacy" => %{}}}, "legacy") == %{}
  end
end
