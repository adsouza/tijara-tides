defmodule TijaraTides.Domain.ShipMaintenance do
  @moduledoc "Published age curve and partition-independent integer maintenance charges."
  @day 86_400_000
  @life 28 * @day
  @residual_bps 2000
  @crossover_bps 1500
  @base_bps 2000

  def useful_life_ms, do: @life
  def residual_bps, do: @residual_bps
  def crossover_ms, do: div(@life * @crossover_bps, 10_000)

  # Published to players; keep the disclosed figures derived from the curve itself.
  def curve,
    do: %{
      life_days: @life / @day,
      crossover_days: (@life + crossover_ms()) / @day,
      residual_percent: div(@residual_bps, 100)
    }

  # Flat base maintenance totals 20% of replacement price over useful life.
  # At 115% of useful life, the extra rate equals replacement depreciation.
  # Differences of the cumulative integral preserve cents across ticks/restarts,
  # including a tick crossing the useful-life boundary. No retroactive billing.
  # A window that runs backwards settles nothing rather than failing the whole tick.
  def cost(_class_id, _built_ms, from_ms, to_ms) when to_ms < from_ms, do: 0

  def cost(class_id, built_ms, from_ms, to_ms) do
    price = TijaraTides.Domain.ShipClass.all()[class_id]["price"]
    built = built_ms || from_ms
    cumulative(price, max(0, to_ms - built)) - cumulative(price, max(0, from_ms - built))
  end

  def estimate(ship, from_ms, to_ms),
    do: cost(ship["class"], ship["built_ms"], from_ms, to_ms)

  defp cumulative(price, age) do
    excess = max(0, age - @life)

    div(price * @base_bps * age, 10_000 * @life) +
      div(
        price * (10_000 - @residual_bps) * excess * excess,
        20_000 * @life * crossover_ms()
      )
  end

  def forecast(ship, now) do
    %{
      next_day: estimate(ship, now, now + @day),
      next_week: estimate(ship, now, now + 7 * @day),
      replacement_day: cost(ship["class"], now, now, now + @day)
    }
  end
end
