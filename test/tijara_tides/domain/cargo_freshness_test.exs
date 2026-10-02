defmodule TijaraTides.Domain.CargoFreshnessTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{CargoFreshness, CargoRules}
  alias TijaraTides.Domain.Ship.{CargoBatch, CargoRows}
  defp fruit, do: %{"shelf_ms" => 1000}

  defp batch,
    do: %CargoBatch{
      good: "fruit",
      quantity: 4,
      lot_id: "parent",
      expires_ms: 1000,
      unit_cost: 100
    }

  test "cooling slows age and warming preserves it without resetting harvest time" do
    cold = CargoFreshness.recondition(batch(), 200, 2500, fruit())
    assert cold.expires_ms == 3400
    assert CargoFreshness.fraction(cold, 600, fruit()) == 7000
    warm = CargoFreshness.recondition(cold, 600, 10_000, fruit())
    assert warm.expires_ms == 1300
    assert warm.freshness["harvest_ms"] == 0
    assert CargoFreshness.origin(warm) == 1000
    assert CargoFreshness.fraction(warm, 600, fruit()) == 7000
    assert CargoFreshness.recondition(warm, 600, 2500).expires_ms == cold.expires_ms
    assert CargoRows.decode(CargoRows.encode(warm)) == warm
  end

  test "minimum life uses the receiver's rate and never revives spoiled batches" do
    assert CargoRules.qualifies_batch?(batch(), 0, 4000, 2500)
    refute CargoRules.qualifies_batch?(batch(), 0, 4001, 2500)
    cold = CargoFreshness.recondition(batch(), 0, 2500, fruit())
    assert cold.expires_ms == 4000
    assert CargoRules.qualifies_batch?(cold, 2000, 500, 10_000)
    refute CargoRules.qualifies_batch?(cold, 2000, 501, 10_000)
    refute CargoRules.qualifies_batch?(cold, 4000, 0, 2500)
    assert CargoRules.qualifies_batch?(%{batch() | expires_ms: nil}, 1000, 2_592_000_000, 2500)
    assert batch().expires_ms == 1000
  end

  test "partial sales inherit exact age and immutable split identity" do
    cold = CargoFreshness.recondition(batch(), 200, 3333, fruit())
    {lots, [sold], [kept]} = CargoBatch.take(%{clock_ms: 701, new_lots: []}, [cold], 1, "fruit")
    assert sold.freshness == kept.freshness
    assert sold.expires_ms == cold.expires_ms

    assert Enum.all?(
             lots.new_lots,
             &(&1["expires_ms"] == 1000 and &1["parent_lot_id"] == "parent")
           )

    assert CargoFreshness.remaining_units(sold, 701) == 8_000_000 - 501 * 3333
    assert CargoFreshness.remaining_units(kept, 701) == CargoFreshness.remaining_units(sold, 701)
  end

  test "cooling cannot revive spoiled cargo and ordinary holds accept perishables" do
    dead = CargoFreshness.recondition(batch(), 1000, 2500, fruit())
    assert dead.expires_ms == 1000
    refute CargoRules.qualifies?(dead.expires_ms, 1000, 0)
    assert CargoFreshness.fraction(dead, 1000, fruit()) == 0
    assert CargoRules.compatible_class_id?("freighter", %{"hold" => "reefer"})
    refute CargoRules.compatible_class_id?("tanker", %{"hold" => "reefer"})
    assert CargoFreshness.rate("reefer", %{"refrigeration" => %{"aging_bps" => 5000}}) == 5000
  end
end
