defmodule TijaraTides.Domain.CargoRules do
  @moduledoc "Hold compatibility, handling durations and perishable freshness estimates."
  alias TijaraTides.Domain.ShipClass

  def compatible_class?(ship, item), do: compatible_class_id?(ship["class"], item)

  def compatible_class_id?(class, item) do
    hold = ShipClass.all()[class]["hold"]

    item["hold"] == hold or (hold == "reefer" and item["hold"] == "dry") or
      (hold == "dry" and item["hold"] == "reefer")
  end

  def compatible_cargo?(ship, item) do
    hold = ShipClass.all()[ship["class"]]["hold"]

    compatible_class?(ship, item) and
      (hold != "liquid" or Enum.all?(ship["cargo"], &(&1["good"] == item["id"])))
  end

  def condition_rows(batches, class, now, catalogue \\ %{}) do
    rate = TijaraTides.Domain.CargoFreshness.rate(ShipClass.all()[class]["hold"], catalogue)

    Enum.map(batches, fn b ->
      batch = %TijaraTides.Domain.Ship.CargoBatch{
        good: Map.get(b, "good", ""),
        quantity: b["quantity"],
        lot_id: b["lot_id"],
        expires_ms: b["expires_ms"],
        freshness: b["freshness"]
      }

      batch
      |> TijaraTides.Domain.CargoFreshness.recondition(now, rate)
      |> TijaraTides.Domain.Ship.CargoRows.encode()
    end)
  end

  def valid_age_row?(row),
    do:
      TijaraTides.Domain.CargoFreshness.valid?(%{
        freshness: row["freshness"],
        expires_ms: row["expires_ms"]
      })

  # Compatibility for callers without a catalogue; world operations use snapshotted profiles.
  def handling_ms(quantity),
    do: handling_ms(quantity, %{"base_ms" => 500, "cargo_bps" => 10_000, "minimum_ms" => 1000})

  def handling_profile(port, good, catalogue) do
    tuning = catalogue["handling"] || %{}
    speeds = tuning["speed_ms_per_lot"] || %{"slow" => 500, "med" => 350, "fast" => 250}

    factors =
      tuning["cargo_bps"] || %{"Perishables" => 12_500, "Scrap" => 15_000, "liquid" => 7500}

    item = (catalogue["goods"] || %{})[good] || %{}
    speed = get_in(catalogue, ["ports", port, "tiers", "speed"]) || "slow"
    kind = if item["hold"] == "liquid", do: "liquid", else: item["category"]

    %{
      "base_ms" => speeds[speed] || 500,
      "cargo_bps" => factors[kind] || 10_000,
      "minimum_ms" => tuning["minimum_ms"] || 1000
    }
  end

  def handling_ms(quantity, profile) do
    max(
      profile["minimum_ms"],
      div(max(0, quantity) * profile["base_ms"] * profile["cargo_bps"] + 9999, 10_000)
    )
  end

  def handling_ms(quantity, port, good, catalogue),
    do: handling_ms(quantity, handling_profile(port, good, catalogue))

  @doc "Lots one command may move, whether traded with a market or transferred to storage."
  def max_lots, do: 10_000

  def max_remaining_ms, do: 2_592_000_000

  def valid_remaining?(minimum),
    do: is_integer(minimum) and minimum >= 0 and minimum <= max_remaining_ms()

  @doc "Minimum life is checked at settlement; nonperishable cargo has unlimited life."
  def qualifies?(nil, _clock, _minimum), do: true
  def qualifies?(expiry, clock, minimum), do: expiry > clock and expiry - clock >= minimum

  def freshness(batches, quantity, clock, elapsed) do
    {expiries, _} =
      Enum.reduce(batches, {[], max(0, quantity)}, fn batch, {expiries, left} ->
        take = min(left, batch["quantity"])

        expiries =
          if take > 0 and batch["expires_ms"],
            do: [batch["expires_ms"] | expiries],
            else: expiries

        {expiries, left - take}
      end)

    case expiries do
      [] ->
        nil

      _ ->
        first = Enum.min(expiries)

        %{
          "remaining_ms" => max(0, first - clock),
          "after_ms" => max(0, first - clock - elapsed),
          "handling_ms" => elapsed
        }
    end
  end

  def voyage_freshness(ship, clock, duration, destination \\ nil, catalogue \\ %{}) do
    unloading =
      ship["cargo"]
      |> Enum.group_by(& &1["good"])
      |> Enum.map(fn {good, batches} ->
        quantity = Enum.sum(Enum.map(batches, & &1["quantity"]))
        handling_ms(quantity, destination, good, catalogue)
      end)
      |> Enum.sum()

    ship["cargo"]
    |> Enum.group_by(& &1["good"])
    |> Enum.sort()
    |> Enum.flat_map(fn {good, batches} ->
      quantity = Enum.sum(Enum.map(batches, & &1["quantity"]))

      case freshness(batches, quantity, clock, duration) do
        nil ->
          []

        estimate ->
          [
            %{
              "good" => good,
              "quantity" => quantity,
              "arrival_ms" => estimate["after_ms"],
              "unloaded_ms" => max(0, estimate["after_ms"] - unloading)
            }
          ]
      end
    end)
  end
end
