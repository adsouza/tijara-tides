defmodule TijaraTides.Domain.ShipPurchaseTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{Accounts, Finance, Fleet, Game, Journal}

  setup do
    catalogue = TijaraTides.Infrastructure.GameCatalogue.all()
    state = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, catalogue)
    {:ok, state, _} = Accounts.seed_invite(state, "invite")
    {:ok, state, _} = Accounts.redeem(state, "invite", "session", %{id: "account", wall_ms: 0})
    account = Game.get(state, "accounts", "account")
    context = %{id: "company", catalogue: catalogue}
    {:ok, state, _} = Accounts.create_company(state, account, "New Shipping", context)

    %{
      state: state,
      account: Game.get(state, "accounts", "account"),
      context: %{context | id: "ship"}
    }
  end

  test "empty companies borrow explicitly, then exchange cash for a ship without profit", c do
    assert Game.get(c.state, "companies", "company")["cash"] == 0
    assert Game.entities(c.state, "ships") == %{}
    assert Finance.summary(c.state, c.account)["available"] == 25_000_000
    assert {:error, :loan_limit} = Finance.borrow(c.state, c.account, 25_000_001, "loan")

    assert {:error, :ship_purchase_funds} =
             Fleet.purchase(c.state, c.account, "freighter", "Jakarta", 4_000_000, c.context)

    {:ok, state, _} = Finance.borrow(c.state, c.account, 10_000_000, "loan")

    {:ok, state, result} =
      Fleet.purchase(
        Journal.clear(state),
        c.account,
        "freighter",
        "Jakarta",
        4_000_000,
        c.context
      )

    assert result == %{"ship_id" => "ship", "spent" => 4_000_000}
    assert %{"cash" => 6_000_000, "profit" => 0} = Game.get(state, "companies", "company")

    assert %{"port" => "Jakarta", "cargo" => [], "status" => "docked", "book_value" => 4_000_000} =
             Game.get(state, "ships", "ship")

    assert Finance.summary(state, c.account)["available"] == 15_000_000
    assert [%{entries: [{"fleet", 4_000_000}, {"cash_available", -4_000_000}]}] = state.journal

    assert {:error, :ship_id_conflict} =
             Fleet.purchase(state, c.account, "freighter", "Jakarta", 4_000_000, c.context)
  end

  test "depreciation is linear, bottoms at residual, and selling records the loss", c do
    {:ok, state, _} = Finance.borrow(c.state, c.account, 10_000_000, "loan")

    {:ok, state, _} =
      Fleet.purchase(state, c.account, "freighter", "Jakarta", 4_000_000, c.context)

    ship = Game.get(state, "ships", "ship")
    assert Fleet.sale_value(ship, 0) == %{book: 4_000_000, proceeds: 3_600_000}
    assert Fleet.sale_value(ship, 14 * 86_400_000) == %{book: 2_400_000, proceeds: 2_160_000}
    assert Fleet.sale_value(ship, 100 * 86_400_000) == %{book: 800_000, proceeds: 720_000}
    assert {:error, :ship_sale_price_changed} = Fleet.sell(state, c.account, "ship", 3_600_001)

    assert {:error, :ship_not_owned} =
             Fleet.sell(state, %{c.account | "id" => "other"}, "ship", 0)

    busy = put_in(state, [:entities, "ships", "ship", "status"], "loading")
    assert {:error, :ship_sale_unavailable} = Fleet.sell(busy, c.account, "ship", 0)
    loaded = put_in(state, [:entities, "ships", "ship", "cargo"], [%{"good" => "lumber"}])
    assert {:error, :ship_sale_unavailable} = Fleet.sell(loaded, c.account, "ship", 0)
    planned = put_in(state, [:entities, "visit_plans"], %{"plan" => %{"ship_id" => "ship"}})
    assert {:error, :ship_sale_unavailable} = Fleet.sell(planned, c.account, "ship", 0)

    {:ok, sold, %{"proceeds" => 3_600_000}} =
      Fleet.sell(Journal.clear(state), c.account, "ship", 3_600_000)

    assert Game.get(sold, "ships", "ship") == nil
    assert Game.get(sold, "companies", "company")["cash"] == 9_600_000
    assert Game.get(sold, "companies", "company")["profit"] == -400_000

    assert [
             %{
               entries: [
                 {"cash_available", 3_600_000},
                 {"fleet", -4_000_000},
                 {"ship_disposal_expense", 400_000}
               ]
             }
           ] = sold.journal
  end

  test "ship purchases validate class, port, quote, ownership and reserved cash", c do
    {:ok, state, _} = Finance.borrow(c.state, c.account, 10_000_000, "loan")

    assert {:error, :ship_class_invalid} =
             Fleet.purchase(state, c.account, "missing", "Jakarta", 4_000_000, c.context)

    assert {:error, :invalid_port} =
             Fleet.purchase(state, c.account, "freighter", "missing", 4_000_000, c.context)

    for price <- [nil, "4000000", 3_999_999] do
      assert {:error, :ship_price_changed} =
               Fleet.purchase(state, c.account, "freighter", "Jakarta", price, c.context)
    end

    assert {:error, :ship_company_unavailable} =
             Fleet.purchase(
               state,
               %{c.account | "id" => "stranger"},
               "freighter",
               "Jakarta",
               4_000_000,
               c.context
             )

    reserved = put_in(state, [:entities, "companies", "company", "reserved"], 6_000_001)

    assert {:error, :ship_purchase_funds} =
             Fleet.purchase(reserved, c.account, "freighter", "Jakarta", 4_000_000, c.context)
  end
end
