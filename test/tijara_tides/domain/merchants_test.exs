defmodule TijaraTides.Domain.MerchantsTest do
  use ExUnit.Case, async: true

  alias TijaraTides.Domain.{
    Game,
    State,
    PortCargoMarketWorld,
    MerchantWarehouseWorld,
    WarehouseWorld,
    CargoLots
  }

  setup do
    cat = TijaraTides.Infrastructure.GameCatalogue.all()
    state = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, cat)
    %{cat: cat, state: state, id: "Singapore|electronics"}
  end

  test "merchants pay for shared capacity and resale preserves delivered lot identity", c do
    s = c.state
    w = MerchantWarehouseWorld.fetch(s, c.id)
    assert w != nil
    assert WarehouseWorld.used(s, w.port, w.storage) >= w.blocks
    before = State.get(s, "markets", c.id)
    assert before["stock"] == 0
    assert before["budget"] < c.cat["goods"]["electronics"]["reference_cents"] * 1000
    {s, batch} = CargoLots.create(s, "electronics", 3, nil)
    cargo = [Map.merge(batch, %{"good" => "electronics", "unit_cost" => 100})]
    s = PortCargoMarketWorld.accept_cargo(s, "Singapore", "electronics", 3, 100, cargo)
    assert State.get(s, "markets", c.id)["stock"] == 3
    assert PortCargoMarketWorld.quote(s, c.cat, "Singapore", "electronics")["manual"]

    {s, sold} =
      PortCargoMarketWorld.release_stock(
        s,
        "Singapore",
        "electronics",
        3,
        200,
        c.cat["goods"]["electronics"]
      )

    assert hd(sold)["lot_id"] == batch["lot_id"]
    assert State.get(s, "markets", c.id)["stock"] == 0
    assert State.get(s, "markets", c.id)["budget"] == before["budget"] + 300

    assert_raise ArgumentError, fn ->
      PortCargoMarketWorld.release_stock(
        s,
        "Singapore",
        "electronics",
        1,
        200,
        c.cat["goods"]["electronics"]
      )
    end
  end

  test "unpaid leases stop trading and eventually release occupied storage", c do
    w = MerchantWarehouseWorld.fetch(c.state, c.id)
    {s, batch} = CargoLots.create(c.state, "electronics", 3, nil)

    s =
      PortCargoMarketWorld.accept_cargo(s, "Singapore", "electronics", 3, 100, [
        Map.merge(batch, %{"good" => "electronics", "unit_cost" => 100})
      ])

    m = State.get(s, "markets", c.id)
    s = State.put(s, "markets", c.id, %{m | "budget" => 0})
    s = %{s | clock_ms: w.expires_ms}
    q = PortCargoMarketWorld.quote(s, c.cat, "Singapore", "electronics")
    assert {q["stock"], q["demand"], q["manual"]} == {0, 0, false}

    assert_raise ArgumentError, fn ->
      PortCargoMarketWorld.accept_cargo(s, "Singapore", "electronics", 1, 0, [])
    end

    s = MerchantWarehouseWorld.advance(%{s | clock_ms: w.expires_ms + 43_200_000}, c.cat)
    assert MerchantWarehouseWorld.fetch(s, c.id) == nil
    assert State.get(s, "markets", c.id)["stock"] == 0
    assert State.get(s, "markets", c.id)["batches"] == []
  end

  test "capacity and missing batch backing prevent merchant purchases", c do
    w = MerchantWarehouseWorld.fetch(c.state, c.id)

    assert_raise ArgumentError, fn ->
      PortCargoMarketWorld.accept_cargo(
        c.state,
        "Singapore",
        "electronics",
        w.capacity + 1,
        0,
        []
      )
    end

    assert_raise ArgumentError, fn ->
      PortCargoMarketWorld.accept_cargo(c.state, "Singapore", "electronics", 1, 0)
    end
  end

  test "perishable resale preserves expiry and split lineage; spoiled stock never replenishes",
       c do
    cat = put_in(c.cat, ["ports", "Jakarta", "roles", "fruit"], "exp/imp")
    s = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, cat)
    {s, batch} = CargoLots.create(s, "fruit", 3, 100)

    s =
      PortCargoMarketWorld.accept_cargo(s, "Jakarta", "fruit", 3, 100, [
        Map.merge(batch, %{"good" => "fruit", "unit_cost" => 100})
      ])

    {s, [sold]} =
      PortCargoMarketWorld.release_stock(s, "Jakarta", "fruit", 1, 200, cat["goods"]["fruit"])

    assert sold["expires_ms"] == 100

    assert Enum.find(s.new_lots, &(&1["id"] == sold["lot_id"]))["parent_lot_id"] ==
             batch["lot_id"]

    s = PortCargoMarketWorld.advance(%{s | clock_ms: 300_000}, cat)
    assert State.get(s, "markets", "Jakarta|fruit")["stock"] == 0
    assert State.get(s, "markets", "Jakarta|fruit")["batches"] == []
  end

  test "committed handling hides inventory until completion without discarding its lease", c do
    {s, batch} = CargoLots.create(c.state, "electronics", 3, nil)

    s =
      PortCargoMarketWorld.accept_cargo(s, "Singapore", "electronics", 3, 100, [
        Map.merge(batch, %{"good" => "electronics", "unit_cost" => 100})
      ])

    s = PortCargoMarketWorld.protect_storage(s, "Singapore", "electronics", 1000)
    assert PortCargoMarketWorld.quote(s, c.cat, "Singapore", "electronics")["stock"] == 0
    assert PortCargoMarketWorld.quote(s, c.cat, "Singapore", "electronics")["demand"] == 0

    assert PortCargoMarketWorld.quote(%{s | clock_ms: 1000}, c.cat, "Singapore", "electronics")[
             "stock"
           ] == 3

    assert State.get(s, "markets", c.id)["stock"] == 3
  end
end
