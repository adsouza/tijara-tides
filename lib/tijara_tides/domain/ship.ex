defmodule TijaraTides.Domain.Ship do
  @moduledoc """
  Ship aggregate root. Owns hull, hold, handling and voyage transitions.
  Transitions accept typed state and scoped clock/allocation inputs.
  Settlement services coordinate returned ship changes with cash and journal writes.
  """
  alias TijaraTides.Domain.{CargoRules, ShipClass}

  alias __MODULE__.{CargoBatch, Lots}

  @fields ~w(voyage_path paid_canals id company_id name class book_value build_value built_ms port cargo status arrive_ms destination depart_ms fuel_total fuel_burned crew_remainder last_cost_ms last_liquid voyage_speedup berth_queued_ms berth_granted_ms berth_retry_ms pending_side pending_good pending_quantity pending_limit pending_destination)a
  defstruct @fields ++ [route_plan: nil, visit_orders: [], visit_plans: []]
  @type t :: %__MODULE__{}

  def commission(%__MODULE__{} = ship) do
    unless ship.status == "docked" and ship.cargo == [] and ShipClass.all()[ship.class],
      do: raise(ArgumentError, "A new ship must be an empty docked hull of a known class")

    ship
  end

  def record_purchase(%__MODULE__{} = ship, cargo, now, cleaning, catalogue) do
    docked!(ship)

    unless Enum.all?(cargo, fn %CargoBatch{} = batch ->
             batch.quantity > 0 and
               compatible_cargo?(ship, catalogue["goods"][batch.good])
           end),
           do: raise(ArgumentError, "Purchased cargo is incompatible with the ship")

    next = %{ship | cargo: ship.cargo ++ cargo}
    capacity!(next, catalogue)
    quantity = Enum.sum(Enum.map(cargo, & &1.quantity))

    last =
      if ShipClass.all()[ship.class]["hold"] == "liquid",
        do: hd(cargo).good,
        else: ship.last_liquid

    %{
      next
      | status: "loading",
        arrive_ms: now + CargoRules.handling_ms(quantity) + if(cleaning > 0, do: 60_000, else: 0),
        last_liquid: last
    }
  end

  def record_sale(%Lots{} = lots, %__MODULE__{} = ship, good, quantity) do
    docked!(ship)

    unless is_integer(quantity) and quantity > 0 and quantity <= aboard(ship, good),
      do: raise(ArgumentError, "Sale requires a positive integer quantity available aboard")

    {lots, sold, remaining} =
      CargoBatch.take(lots, ship.cargo, quantity, good)

    next = %{
      ship
      | cargo: remaining,
        status: "unloading",
        arrive_ms: lots.clock_ms + CargoRules.handling_ms(quantity)
    }

    {lots, next, sold}
  end

  def begin_voyage(%__MODULE__{} = ship, destination, estimate, now, speedup) do
    docked!(ship)

    unless is_binary(destination) and destination != ship.port and
             is_integer(estimate["duration_ms"]) and estimate["duration_ms"] > 0 and
             is_integer(estimate["fuel"]) and estimate["fuel"] >= 0,
           do: raise(ArgumentError, "Voyage needs a different destination and positive duration")

    %{
      ship
      | status: "sailing",
        berth_queued_ms: nil,
        berth_granted_ms: nil,
        pending_side: nil,
        pending_good: nil,
        pending_quantity: nil,
        pending_limit: nil,
        pending_destination: nil,
        voyage_path: nil,
        paid_canals:
          Enum.reduce(estimate["route"]["passages"] || [], 0, fn p, n ->
            Bitwise.bor(n, __MODULE__.canal_bit(p))
          end),
        destination: destination,
        depart_ms: now,
        arrive_ms: now + estimate["duration_ms"],
        fuel_total: estimate["fuel"],
        fuel_burned: 0,
        voyage_speedup: speedup
    }
  end

  def canal_bit("panama"), do: 1
  def canal_bit("suez"), do: 2
  def canal_bit(_), do: 0

  def capacity(%__MODULE__{} = ship, catalogue) do
    Enum.reduce(ship.cargo, %TijaraTides.Domain.Capacity{}, fn batch, totals ->
      item = catalogue["goods"][batch.good]

      %{
        totals
        | weight: totals.weight + item["weight_kg"] * batch.quantity,
          volume: totals.volume + item["volume_l"] * batch.quantity
      }
    end)
  end

  defp capacity!(ship, catalogue) do
    space = capacity(ship, catalogue)
    class = ShipClass.all()[ship.class]
    liquids = Enum.uniq(Enum.map(ship.cargo, & &1.good))

    unless space.weight <= class["weight"] and space.volume <= class["volume"] and
             (class["hold"] != "liquid" or length(liquids) <= 1),
           do: raise(ArgumentError, "Ship hold capacity or liquid segregation violated")
  end

  defp finish_operation(%{status: "sailing"} = ship, arrived_at) do
    %{
      ship
      | port: ship.destination || ship.port,
        destination: nil,
        status: "docked",
        berth_queued_ms: arrived_at,
        berth_granted_ms: nil,
        arrive_ms: nil,
        depart_ms: nil
    }
  end

  # Completing physical work retains admission for the rest of the visit.
  defp finish_operation(%{status: status} = ship, _) when status in ["loading", "unloading"],
    do: %{ship | status: "docked", destination: nil, arrive_ms: nil, depart_ms: nil}

  defp docked!(%{status: "docked"}), do: :ok
  defp docked!(_), do: raise(ArgumentError, "Ship must finish its current operation first")

  def advance(%__MODULE__{} = aggregate, now, elapsed, bankrupt, speedup, book_value) do
    ship = aggregate |> retime_voyage(now - elapsed, speedup)
    depreciation = ship.book_value - book_value
    ship = %{ship | book_value: book_value}
    class = ShipClass.all()[ship.class]
    end_ms = ship.arrive_ms || now

    moving_ms =
      if ship.status == "sailing",
        do: max(0, min(now, end_ms) - ship.last_cost_ms),
        else: 0

    idle_ms = now - ship.last_cost_ms - moving_ms

    crew_numerator =
      ship.crew_remainder + moving_ms * class["crew"] * 2 + idle_ms * class["crew"]

    crew = if not bankrupt, do: div(crew_numerator, 120_000), else: 0

    fuel_burned =
      if ship.status == "sailing",
        do:
          max(
            ship.fuel_burned,
            min(
              ship.fuel_total,
              div(
                ship.fuel_total * max(0, now - ship.depart_ms),
                ship.arrive_ms - ship.depart_ms
              )
            )
          ),
        else: ship.fuel_burned

    fuel = fuel_burned - ship.fuel_burned

    {expired, cargo} =
      Enum.split_with(ship.cargo, &(&1.expires_ms != nil and &1.expires_ms <= now))

    spoilage = Enum.sum(Enum.map(expired, &(&1.unit_cost * &1.quantity)))

    ship = %{
      ship
      | fuel_burned: fuel_burned,
        last_cost_ms: now,
        crew_remainder: rem(crew_numerator, 120_000),
        cargo: cargo
    }

    ship =
      if ship.status != "docked" and end_ms <= now do
        finish_operation(ship, end_ms)
      else
        ship
      end

    next = %{
      ship
      | route_plan: aggregate.route_plan,
        visit_orders: aggregate.visit_orders,
        visit_plans: aggregate.visit_plans
    }

    {next, %{depreciation: depreciation, fuel: fuel, crew: crew, spoilage: spoilage}}
  end

  # Older in-flight voyages used 60x. Preserve their progress when tuning changes;
  # the persisted multiplier prevents applying this adjustment on later ticks.
  defp retime_voyage(%__MODULE__{status: "sailing"} = ship, clock, speedup) do
    previous = ship.voyage_speedup || 60

    if previous == speedup do
      ship
    else
      ship
      |> Map.put(
        :depart_ms,
        clock - div((clock - ship.depart_ms) * previous, speedup)
      )
      |> Map.put(
        :arrive_ms,
        clock + max(1, div((ship.arrive_ms - clock) * previous, speedup))
      )
      |> Map.put(:voyage_speedup, speedup)
    end
  end

  defp retime_voyage(ship, _clock, _speedup), do: ship

  def cargo_available(%__MODULE__{cargo: cargo}, good),
    do: Enum.sum(for batch <- cargo, batch.good == good, do: batch.quantity)

  defp aboard(ship, good), do: cargo_available(ship, good)

  defp compatible_cargo?(ship, item) do
    CargoRules.compatible_class_id?(ship.class, item) and
      (ShipClass.all()[ship.class]["hold"] != "liquid" or
         Enum.all?(ship.cargo, &(&1.good == item["id"])))
  end

  def cancel_automation(%__MODULE__{} = ship) do
    %{
      clear_pending(ship)
      | berth_queued_ms: nil,
        berth_granted_ms: nil,
        route_plan: %__MODULE__.RoutePlan{},
        visit_orders: [],
        visit_plans: []
    }
  end

  def retire(%__MODULE__{} = ship) do
    docked!(ship)

    committed =
      (ship.route_plan != nil and ship.route_plan.header != nil) or ship.visit_plans != [] or
        Enum.any?(ship.visit_orders, &(&1.status in ["planned", "waiting"]))

    if ship.cargo != [] or committed,
      do: raise(ArgumentError, "Cannot retire a ship with cargo or committed work")

    :retired
  end

  def reroute(%__MODULE__{} = ship, destination, quote, paid, now) do
    unless ship.status == "sailing", do: raise(ArgumentError, "Only sailing ships can divert")

    %{
      ship
      | destination: destination,
        voyage_path: quote["route"]["coordinates"],
        paid_canals: paid,
        depart_ms: now,
        arrive_ms: now + quote["duration_ms"],
        fuel_total: quote["fuel"],
        fuel_burned: 0
    }
  end

  def request_berth(%__MODULE__{} = ship, now) do
    if ship.status == "docked" and is_nil(ship.berth_queued_ms) and
         is_nil(ship.berth_granted_ms) and (ship.berth_retry_ms || 0) <= now,
       do: %{ship | berth_queued_ms: now},
       else: ship
  end

  def grant_berth(%__MODULE__{} = ship, now) do
    docked!(ship)

    %{
      ship
      | berth_queued_ms: nil,
        berth_granted_ms: ship.berth_granted_ms || now,
        berth_retry_ms: nil
    }
  end

  def admit_handling(%__MODULE__{} = ship, now) do
    unless ship.status in ["loading", "unloading"],
      do: raise(ArgumentError, "Only handling ships can retain admission")

    %{
      ship
      | berth_queued_ms: nil,
        berth_granted_ms: ship.berth_granted_ms || now,
        berth_retry_ms: nil
    }
  end

  def release_berth(%__MODULE__{} = ship, now, retry_at \\ nil) do
    docked!(ship)

    unless is_nil(retry_at) or (is_integer(retry_at) and retry_at >= now),
      do: raise(ArgumentError, "Berth retry must not be in the past")

    %{ship | berth_queued_ms: nil, berth_granted_ms: nil, berth_retry_ms: retry_at}
  end

  def queue_trade(%__MODULE__{} = ship, %TijaraTides.Domain.Trade{} = trade, now) do
    docked!(ship)

    unless is_nil(ship.pending_side) and trade.side in ["buy", "sell"] and
             is_integer(trade.quantity) and trade.quantity > 0 and is_integer(trade.limit) and
             trade.limit >= 0,
           do: raise(ArgumentError, "Invalid pending berth trade")

    %{
      ship
      | pending_side: trade.side,
        pending_good: trade.good,
        pending_quantity: trade.quantity,
        pending_limit: trade.limit,
        pending_destination: trade.destination
    }
    |> request_berth(now)
  end

  def complete_pending_trade(%__MODULE__{} = ship) do
    unless ship.status in ["loading", "unloading"] and not is_nil(ship.pending_side),
      do: raise(ArgumentError, "No pending trade has started handling")

    clear_pending(ship)
  end

  def cancel_pending_trade(%__MODULE__{} = ship) do
    docked!(ship)
    unless ship.pending_side, do: raise(ArgumentError, "No pending trade to cancel")

    # Give up the ticket and any berth, but keep berth_retry_ms: cancelling must not
    # clear a cooldown a failed admission imposed, or resubmitting would evade it.
    %{clear_pending(ship) | berth_queued_ms: nil, berth_granted_ms: nil}
  end

  defp clear_pending(ship),
    do: %{
      ship
      | pending_side: nil,
        pending_good: nil,
        pending_quantity: nil,
        pending_limit: nil,
        pending_destination: nil
    }
end
