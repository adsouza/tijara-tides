defmodule TijaraTides.Domain.CargoRules do
  @moduledoc "Hold compatibility, handling durations and perishable freshness estimates."
  import TijaraTides.Domain.Fleet, only: [classes: 0]

  def compatible_cargo?(ship, item) do
    hold = classes()[ship["class"]]["hold"]
    supported = item["hold"] == hold or (hold == "reefer" and item["hold"] == "dry")
    supported and (hold != "liquid" or Enum.all?(ship["cargo"], &(&1["good"] == item["id"])))
  end

  def handling_ms(quantity), do: max(1000, quantity * 500)

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
