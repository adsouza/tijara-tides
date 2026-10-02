defmodule TijaraTides.Domain.TransitionReleasesTest do
  # Each transition below must release what it invalidates by itself. These tests
  # call the transition directly, with no reconcile sweep afterwards.
  use ExUnit.Case, async: true

  alias TijaraTides.Domain.{AuctionWorld, CargoLots, CompanyFinanceWorld, Fleet, Game}
  alias TijaraTides.Domain.{OrderBookWorld, State, Warehouse, WarehouseWorld}
  alias TijaraTides.Domain.Services.{Auctions, Bankruptcy, Exchange, RouteEditing}
  alias TijaraTides.Domain.Ship.CargoRows

  setup do
    cat =
      TijaraTides.Infrastructure.GameCatalogue.all()
      |> Map.put("auctions", %{"interval_ms" => 10_000, "window_ms" => 10_000})

    s = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, cat)
    {:ok, s, _} = Game.seed_invite(s, "invite")
    {:ok, s, _} = Game.redeem(s, "invite", "session", %{id: "a", wall_ms: 0})
    a = Game.get(s, "accounts", "a")
    s = State.put(s, "accounts", "b", %{a | "id" => "b"})

    s =
      Enum.reduce(["a", "b"], s, fn id, s ->
        account = Game.get(s, "accounts", id)

        {:ok, s, _} =
          TijaraTides.CompanyFixture.create_company(s, account, id, "Jakarta", "general", %{
            id: id <> "co",
            catalogue: cat
          })

        account = Game.get(s, "accounts", id)

        {:ok, s, _} =
          WarehouseWorld.lease(
            s,
            account,
            %{
              "port" => "Jakarta",
              "storage" => "dry",
              "blocks" => 10,
              "days" => 1,
              "price" => Warehouse.quote(WarehouseWorld.used(s, "Jakarta", "dry"), "dry", 10, 1)
            },
            id <> "w",
            cat
          )

        s
      end)

    m = Game.get(s, "markets", "Jakarta|whisky")
    s = State.put(s, "markets", "Jakarta|whisky", %{m | "stock" => 0, "demand" => 0})
    %{s: s |> stock("lumber", 10) |> stock("whisky", 3, "b"), cat: cat}
  end

  defp stock(s, good, n, owner \\ "a") do
    {s, lot} = CargoLots.create(s, good, n, nil)
    row = Game.get(s, "warehouses", owner <> "w")
    batch = Map.merge(lot, %{"good" => good, "unit_cost" => 100, "expires_ms" => nil})
    batch = CargoRows.encode(CargoRows.decode(batch))

    s
    |> State.put("warehouses", owner <> "w", %{row | "cargo" => row["cargo"] ++ [batch]})
    |> CompanyFinanceWorld.post(owner <> "co", "purchase", [
      {"inventory", n * 100},
      {"cash_available", -n * 100}
    ])
  end

  defp account(s, id), do: Game.get(s, "accounts", id)

  defp claim(s, cat, id, extra \\ %{}) do
    {:ok, s, _} =
      WarehouseWorld.reserve(
        s,
        account(s, "a"),
        Map.merge(
          %{
            "warehouse" => "aw",
            "ship" => "aco:1",
            "good" => "lumber",
            "kind" => "stock",
            "quantity" => 2
          },
          extra
        ),
        id,
        cat
      )

    s
  end

  defp released?(s, id),
    do:
      Game.get(s, "warehouse_reservations", id) == nil and
        Game.get(s, "notices", "reservation:" <> id)["code"] == "warehouse.reservation_released"

  test "selling a ship releases its manual warehouse claims", %{s: s, cat: cat} do
    s = claim(s, cat, "held")
    {:ok, s, _} = Fleet.sell(s, account(s, "a"), "aco:1", 0)
    assert released?(s, "held")
  end

  test "removing a route stop or deleting the route releases claims made for it",
       %{s: s, cat: cat} do
    edit = fn s, cmd, id ->
      {:ok, s, _} =
        RouteEditing.execute(
          s,
          account(s, "a"),
          Map.merge(%{"action" => "route", "ship" => "aco:1"}, cmd),
          %{id: id, catalogue: cat}
        )

      s
    end

    s =
      s
      |> edit.(%{"operation" => "add_stop", "port" => "Jakarta"}, "s1")
      |> edit.(%{"operation" => "add_stop", "port" => "Singapore"}, "s2")
      |> claim(cat, "for-stop", %{"stop_id" => "s1"})
      |> claim(cat, "unrelated", %{"quantity" => 1})

    removed = edit.(s, %{"operation" => "remove_stop", "stop" => "s1"}, "rm")
    assert released?(removed, "for-stop")
    assert Game.get(removed, "warehouse_reservations", "unrelated")

    deleted = edit.(s, %{"operation" => "delete"}, "del")
    assert released?(deleted, "for-stop")
    assert Game.get(deleted, "warehouse_reservations", "unrelated")
  end

  test "receivership withdraws orders, bids and claims within the bankruptcy transition",
       %{s: s, cat: cat} do
    s = claim(s, cat, "held")

    {:ok, s, _} =
      Exchange.place(
        s,
        account(s, "a"),
        %{
          "warehouse" => "aw",
          "good" => "lumber",
          "side" => "sell",
          "quantity" => 3,
          "price" => 900
        },
        "sell",
        cat
      )

    {:ok, s, _} =
      Exchange.place(
        s,
        account(s, "a"),
        %{
          "warehouse" => "aw",
          "good" => "lumber",
          "side" => "buy",
          "quantity" => 2,
          "price" => 50
        },
        "buy",
        cat
      )

    {:ok, s, _} =
      Auctions.consign(
        s,
        account(s, "b"),
        %{"warehouse" => "bw", "good" => "whisky", "quantity" => 3, "price" => 1000},
        "lot",
        cat,
        "seed"
      )

    s = %{s | clock_ms: AuctionWorld.fetch(s, "lot").opens_ms}

    {:ok, s, _} =
      Auctions.bid(
        s,
        account(s, "a"),
        %{"auction" => "lot", "warehouse" => "aw", "price" => 2001},
        "bid",
        cat
      )

    assert [_] = AuctionWorld.company_bids(s, "aco")
    assert Game.get(s, "companies", "aco")["reserved"] > 0

    {:ok, s, _} = Bankruptcy.bankrupt(s, account(s, "a"), "forced")

    assert OrderBookWorld.company_orders(s, "aco") == []
    assert Game.get(s, "notices", "exchange:sell")["code"] == "exchange.cancelled"
    assert AuctionWorld.company_bids(s, "aco") == []
    assert AuctionWorld.fetch(s, "lot").status == "scheduled"
    assert Game.get(s, "companies", "aco")["reserved"] == 0
    assert released?(s, "held")
    assert State.owned(s, "warehouse_reservations", "company_id", "aco") == []
  end
end
