defmodule TijaraTides.Domain.ParticipationTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{Participation, ParticipationWorld, PortCargoMarket, State}
  alias TijaraTides.Domain.PortCargoMarket.Lots

  test "weights decay on wall time, cap at one, and ignore closed companies" do
    settings = Participation.settings(%{})
    assert Participation.weight(nil, 0, settings) == 0
    assert Participation.weight(100, 0, settings) == 10_000
    assert Participation.weight(0, 604_800_000, settings) == 3679
    assert Participation.weight(0, 4 * 604_800_000, settings) == 183

    state =
      %{entities: %{}, clock_ms: 0}
      |> State.put("companies", "a", %{"bankruptcy_ms" => nil})
      |> State.put("companies", "b", %{"bankruptcy_ms" => 0})
      |> State.put("company_activity", "a", %{"last_action_ms" => 0})
      |> State.put("company_activity", "b", %{"last_action_ms" => 0})

    assert ParticipationWorld.index(state, 0, %{}) == 10_000
    assert ParticipationWorld.index(state, 604_800_000, %{}) == 3679
  end

  test "only substantial economic events refresh activity, including automated trades" do
    before = %{entities: %{"companies" => %{"a" => %{"bankruptcy_ms" => nil}}}}

    event = %{
      company: "a",
      kind: "sale",
      entries: [{"sales_revenue", -10_000}, {"cash_available", 10_000}]
    }

    active = ParticipationWorld.observe(before, Map.put(before, :journal, [event]), 123, %{})
    assert State.get(active, "company_activity", "a")["last_action_ms"] == 123

    for invalid <- [
          %{event | kind: "crew"},
          %{event | entries: [{"sales_revenue", -9999}]},
          %{event | kind: "auction_escrow", entries: [{"cash_reserved", -10_000}]}
        ] do
      unchanged = Map.put(before, :journal, [invalid])
      assert ParticipationWorld.observe(before, unchanged, 123, %{}) == unchanged
    end

    assert ParticipationWorld.observe(active, active, 999, %{}) == active
  end

  test "fractional credits conserve production across ticks and zero participation creates nothing" do
    market = %PortCargoMarket{
      port: "p",
      good: "lumber",
      seller: true,
      buyer: true,
      merchant: false,
      stock: 0,
      demand: 0,
      budget: 0,
      batches: [],
      last_production: 0
    }

    item = %{"id" => "lumber", "shelf_ms" => 0, "reference_cents" => 100}
    {_, first} = PortCargoMarket.replenish(%Lots{clock_ms: 150_000}, market, item, 5000)
    assert {first.stock, first.production_credit} == {0, 5000}
    {_, second} = PortCargoMarket.replenish(%Lots{clock_ms: 300_000}, first, item, 5000)
    {_, together} = PortCargoMarket.replenish(%Lots{clock_ms: 300_000}, market, item, 5000)
    assert second == together
    assert {second.stock, second.budget, second.production_credit} == {1, 100, 0}
    {_, stopped} = PortCargoMarket.replenish(%Lots{clock_ms: 300_000}, market, item, 0)
    assert {stopped.stock, stopped.budget, stopped.demand} == {0, 0, 0}

    {_, capped} =
      PortCargoMarket.replenish(%Lots{clock_ms: 3 * 604_800_000}, market, item, 20_000)

    assert capped.stock == 500
    assert capped.budget == 100 * div(604_800_000, 150_000) * 2
  end
end
