defmodule TijaraTides.Domain.ShipMaintenanceTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{ShipMaintenance, ShipClass, Ship, CompanyFinanceWorld}
  @day 86_400_000

  test "flat useful-life costs become more expensive than replacement at the published crossover" do
    life = ShipMaintenance.useful_life_ms()
    cross = ShipMaintenance.crossover_ms()

    for {class, specification} <- ShipClass.all() do
      base = ShipMaintenance.cost(class, 0, 0, @day)
      assert abs(ShipMaintenance.cost(class, 0, life - @day, life) - base) <= 1
      replacement = base + div(specification["price"] * 8000 * @day, 10_000 * life)
      assert ShipMaintenance.cost(class, 0, life + cross - @day, life + cross) < replacement
      assert ShipMaintenance.cost(class, 0, life + cross, life + cross + @day) > replacement
    end
  end

  test "charges are additive across life boundaries, fractional cents, pauses and reloads" do
    life = ShipMaintenance.useful_life_ms()
    points = [0, 1, 99, life - 1, life, life + 1, life + @day, 2 * life]

    parts =
      points
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> ShipMaintenance.cost("freighter", 0, a, b) end)

    assert Enum.sum(parts) == ShipMaintenance.cost("freighter", 0, 0, 2 * life)
    assert ShipMaintenance.cost("freighter", 0, life, life) == 0
    # Loading a persisted last-cost timestamp bills only the newly advanced interval.
    ship = %Ship{
      class: "freighter",
      built_ms: 0,
      last_cost_ms: life,
      status: "docked",
      cargo: [],
      book_value: 800_000,
      crew_remainder: 0,
      fuel_total: 0,
      fuel_burned: 0
    }

    {next, effects} = Ship.advance(ship, life + @day, @day, false, 600, ship.book_value)
    assert effects.maintenance == ShipMaintenance.cost("freighter", 0, life, life + @day)
    {_, again} = Ship.advance(next, life + @day, 0, false, 600, next.book_value)
    assert again.maintenance == 0
    {_, bankrupt} = Ship.advance(ship, life + @day, @day, true, 600, ship.book_value)
    assert bankrupt.maintenance == 0
  end

  test "purchase funding includes aging maintenance for the whole fleet through loading and arrival" do
    now = 2 * ShipMaintenance.useful_life_ms()
    cat = TijaraTides.Infrastructure.GameCatalogue.all()

    ship = %{
      "id" => "s",
      "class" => "freighter",
      "built_ms" => now,
      "last_cost_ms" => now,
      "crew_remainder" => 0,
      "status" => "docked",
      "port" => "Jakarta",
      "cargo" => []
    }

    old = %{ship | "id" => "old", "built_ms" => 0}

    quote =
      TijaraTides.Domain.Services.TradeSettlement.purchase_voyage(
        ship,
        cat["goods"]["lumber"],
        1,
        "Singapore",
        [ship],
        now,
        cat
      )

    fleet_quote =
      TijaraTides.Domain.Services.TradeSettlement.purchase_voyage(
        ship,
        cat["goods"]["lumber"],
        1,
        "Singapore",
        [ship, old],
        now,
        cat
      )

    horizon = quote["loading_ms"] + quote["duration_ms"]
    old_crew = div(horizon * ShipClass.all()["freighter"]["crew"] + 119_999, 120_000)

    assert fleet_quote["required"] - quote["required"] ==
             old_crew + ShipMaintenance.estimate(old, now, now + horizon)

    assert quote["maintenance_estimate"] ==
             ShipMaintenance.estimate(ship, now + quote["loading_ms"], now + horizon)
  end

  test "maintenance posts separately and creates arrears without spending reserved cash" do
    company = %{"id" => "c", "cash" => 1000, "reserved" => 900, "unpaid" => 0, "profit" => 0}
    state = %{clock_ms: 20, entities: %{"companies" => %{"c" => company}}}

    next =
      CompanyFinanceWorld.ship_operations(state, "c", "s", %{
        crew: 50,
        maintenance: 200,
        fuel: 0,
        depreciation: 0,
        spoilage: 0
      })

    assert %{"cash" => 900, "reserved" => 900, "unpaid" => 150, "profit" => -250} =
             next.entities["companies"]["c"]

    entries = Enum.flat_map(next.journal, & &1.entries)
    assert {"maintenance_expense", 200} in entries
    assert {"crew_expense", 50} in entries
    assert Enum.sum(Enum.map(entries, &elem(&1, 1))) == 0
  end
end
