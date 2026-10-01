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

  def handling_ms(quantity), do: max(1000, quantity * 500)

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

  def voyage_freshness(ship, clock, duration) do
    unloading = ship["cargo"] |> Enum.map(& &1["quantity"]) |> Enum.sum() |> handling_ms()

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
