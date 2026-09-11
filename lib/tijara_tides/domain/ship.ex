defmodule TijaraTides.Domain.Ship do
  @moduledoc """
  Ship aggregate root. Owns hull, hold, handling and voyage transitions.
  World rows are an adapter representation, never the API for a ship transition.
  Settlement services coordinate returned ship changes with cash and journal writes.
  """
  alias TijaraTides.Domain.{CargoRules, ShipClass, State}

  @fields ~w(id company_id name class book_value build_value built_ms port cargo status arrive_ms destination depart_ms fuel_total fuel_burned crew_remainder last_cost_ms last_liquid voyage_speedup)a
  defstruct @fields ++ [route_plan: nil, visit_orders: [], visit_plans: []]
  @type t :: %__MODULE__{}

  def from_row(row) do
    struct!(__MODULE__, Map.new(@fields, &{&1, row[Atom.to_string(&1)]}))
  end

  def from_world(state, id) do
    ship = from_row(State.get(state, "ships", id))

    %{
      ship
      | route_plan: __MODULE__.RoutePlan.load(state, id),
        visit_orders:
          State.entities(state, "ship_instructions")
          |> Map.values()
          |> Enum.filter(&(&1["ship_id"] == id))
          |> Enum.map(&__MODULE__.VisitOrder.from_row/1),
        visit_plans:
          State.entities(state, "visit_plans")
          |> Map.values()
          |> Enum.filter(&(&1["ship_id"] == id))
    }
  end

  def to_row(%__MODULE__{} = ship) do
    Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(ship, &1)})
    |> then(fn row ->
      if ship.voyage_speedup == nil, do: Map.delete(row, "voyage_speedup"), else: row
    end)
  end

  def commission(row) do
    ship = from_row(row)

    unless ship.status == "docked" and ship.cargo == [] and ShipClass.all()[ship.class],
      do: raise(ArgumentError, "A new ship must be an empty docked hull of a known class")

    ship
  end

  def record_purchase(%__MODULE__{} = ship, cargo, now, cleaning, catalogue) do
    docked!(ship)
    row = to_row(ship)

    unless Enum.all?(cargo, fn batch ->
             batch["quantity"] > 0 and
               CargoRules.compatible_cargo?(row, catalogue["goods"][batch["good"]])
           end),
           do: raise(ArgumentError, "Purchased cargo is incompatible with the ship")

    next = %{ship | cargo: ship.cargo ++ cargo}
    capacity!(next, catalogue)
    quantity = Enum.sum(Enum.map(cargo, & &1["quantity"]))

    last =
      if ShipClass.all()[ship.class]["hold"] == "liquid",
        do: hd(cargo)["good"],
        else: ship.last_liquid

    %{
      next
      | status: "loading",
        arrive_ms: now + CargoRules.handling_ms(quantity) + if(cleaning > 0, do: 60_000, else: 0),
        last_liquid: last
    }
  end

  def record_sale(%__MODULE__{} = ship, sold, remaining, now) do
    docked!(ship)

    unless quantities(ship.cargo) == quantities(sold ++ remaining),
      do: raise(ArgumentError, "Sale must conserve the ship's cargo quantities")

    quantity = Enum.sum(Enum.map(sold, & &1["quantity"]))
    unless quantity > 0, do: raise(ArgumentError, "Sale must unload positive cargo")

    %{
      ship
      | cargo: remaining,
        status: "unloading",
        arrive_ms: now + CargoRules.handling_ms(quantity)
    }
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
        destination: destination,
        depart_ms: now,
        arrive_ms: now + estimate["duration_ms"],
        fuel_total: estimate["fuel"],
        fuel_burned: 0,
        voyage_speedup: speedup
    }
  end

  def capacity(%__MODULE__{} = ship, catalogue) do
    Enum.reduce(ship.cargo, %TijaraTides.Domain.Capacity{}, fn batch, totals ->
      item = catalogue["goods"][batch["good"]]

      %{
        totals
        | weight: totals.weight + item["weight_kg"] * batch["quantity"],
          volume: totals.volume + item["volume_l"] * batch["quantity"]
      }
    end)
  end

  defp capacity!(ship, catalogue) do
    space = capacity(ship, catalogue)
    class = ShipClass.all()[ship.class]
    liquids = Enum.uniq(Enum.map(ship.cargo, & &1["good"]))

    unless space.weight <= class["weight"] and space.volume <= class["volume"] and
             (class["hold"] != "liquid" or length(liquids) <= 1),
           do: raise(ArgumentError, "Ship hold capacity or liquid segregation violated")
  end

  defp quantities(cargo),
    do:
      Enum.reduce(cargo, %{}, fn b, acc ->
        Map.update(acc, b["good"], b["quantity"], &(&1 + b["quantity"]))
      end)

  defp docked!(%{status: "docked"}), do: :ok
  defp docked!(_), do: raise(ArgumentError, "Ship must finish its current operation first")

  def advance(%__MODULE__{} = aggregate, now, elapsed, bankrupt, speedup, book_value) do
    ship = aggregate |> to_row() |> retime_voyage(now - elapsed, speedup)
    depreciation = ship["book_value"] - book_value
    ship = Map.put(ship, "book_value", book_value)
    class = ShipClass.all()[ship["class"]]
    end_ms = ship["arrive_ms"] || now

    moving_ms =
      if ship["status"] == "sailing",
        do: max(0, min(now, end_ms) - ship["last_cost_ms"]),
        else: 0

    idle_ms = now - ship["last_cost_ms"] - moving_ms

    crew_numerator =
      ship["crew_remainder"] + moving_ms * class["crew"] * 2 + idle_ms * class["crew"]

    crew = if not bankrupt, do: div(crew_numerator, 120_000), else: 0

    fuel_burned =
      if ship["status"] == "sailing",
        do:
          max(
            ship["fuel_burned"],
            min(
              ship["fuel_total"],
              div(
                ship["fuel_total"] * max(0, now - ship["depart_ms"]),
                ship["arrive_ms"] - ship["depart_ms"]
              )
            )
          ),
        else: ship["fuel_burned"]

    fuel = fuel_burned - ship["fuel_burned"]

    {expired, cargo} =
      Enum.split_with(ship["cargo"], &(&1["expires_ms"] != nil and &1["expires_ms"] <= now))

    spoilage = Enum.sum(Enum.map(expired, &(&1["unit_cost"] * &1["quantity"])))

    ship = %{
      ship
      | "fuel_burned" => fuel_burned,
        "last_cost_ms" => now,
        "crew_remainder" => rem(crew_numerator, 120_000),
        "cargo" => cargo
    }

    ship =
      if ship["status"] != "docked" and end_ms <= now do
        %{
          ship
          | "port" => ship["destination"] || ship["port"],
            "destination" => nil,
            "status" => "docked",
            "arrive_ms" => nil,
            "depart_ms" => nil
        }
      else
        ship
      end

    next = %{
      from_row(ship)
      | route_plan: aggregate.route_plan,
        visit_orders: aggregate.visit_orders,
        visit_plans: aggregate.visit_plans
    }

    {next, %{depreciation: depreciation, fuel: fuel, crew: crew, spoilage: spoilage}}
  end

  # Older in-flight voyages used 60x. Preserve their progress when tuning changes;
  # the persisted multiplier prevents applying this adjustment on later ticks.
  defp retime_voyage(%{"status" => "sailing"} = ship, clock, speedup) do
    previous = Map.get(ship, "voyage_speedup", 60)

    if previous == speedup do
      ship
    else
      ship
      |> Map.put(
        "depart_ms",
        clock - div((clock - ship["depart_ms"]) * previous, speedup)
      )
      |> Map.put(
        "arrive_ms",
        clock + max(1, div((ship["arrive_ms"] - clock) * previous, speedup))
      )
      |> Map.put("voyage_speedup", speedup)
    end
  end

  defp retime_voyage(ship, _clock, _speedup), do: ship

  defdelegate edit_route(state, account, params, context), to: __MODULE__.RoutePlan, as: :execute
  defdelegate route_stops(state, ship), to: __MODULE__.RoutePlan, as: :stops
  defdelegate automation_enabled?(state, ship), to: __MODULE__.RoutePlan, as: :executable?
  defdelegate prepare_visits(state, catalogue), to: __MODULE__.RoutePlan, as: :advance
  defdelegate route_departed(state, ship, destination), to: __MODULE__.RoutePlan, as: :departed

  defdelegate add_instruction(state, account, params, context),
    to: __MODULE__.VisitOrders,
    as: :add

  defdelegate change_onward(state, account, ship, port, onward, catalogue, auto_depart),
    to: __MODULE__.VisitOrders

  defdelegate cancel_instruction(state, account, id, catalogue),
    to: __MODULE__.VisitOrders,
    as: :cancel

  defdelegate consume_departure(state, ship, destination, catalogue),
    to: __MODULE__.VisitOrders,
    as: :depart

  defdelegate execute_visits(state, catalogue), to: __MODULE__.VisitOrders, as: :advance

  @automation ~w(route_rules route_stops ship_routes ship_instructions visit_plans)
  def cancel_automation(state, ship_id) do
    Enum.reduce(@automation, state, fn kind, state ->
      Enum.reduce(State.entities(state, kind), state, fn {id, row}, state ->
        if row["ship_id"] == ship_id, do: State.delete(state, kind, id), else: state
      end)
    end)
  end

  def retire(state, ship_id) do
    ship = from_world(state, ship_id)
    docked!(ship)

    committed =
      ship.route_plan.header != nil or ship.visit_plans != [] or
        Enum.any?(ship.visit_orders, &(&1.status in ["planned", "waiting"]))

    if ship.cargo != [] or committed,
      do: raise(ArgumentError, "Cannot retire a ship with cargo or committed work")

    state |> cancel_automation(ship_id) |> State.delete("ships", ship_id)
  end

  def commission(state, row) do
    if State.get(state, "ships", row["id"]), do: raise(ArgumentError, "Ship already exists")
    store(state, commission(row))
  end

  def load_cargo(state, id, cargo, cleaning, catalogue) do
    ship = State.get(state, "ships", id) |> from_row()
    store(state, record_purchase(ship, cargo, state.clock_ms, cleaning, catalogue))
  end

  def unload_cargo(state, id, sold, remaining) do
    ship = State.get(state, "ships", id) |> from_row()
    store(state, record_sale(ship, sold, remaining, state.clock_ms))
  end

  def depart(state, id, destination, estimate, speedup) do
    ship = State.get(state, "ships", id) |> from_row()
    store(state, begin_voyage(ship, destination, estimate, state.clock_ms, speedup))
  end

  def advance_hull(state, id, elapsed, bankrupt, speedup, book_value) do
    ship = State.get(state, "ships", id) |> from_row()
    {next, effects} = advance(ship, state.clock_ms, elapsed, bankrupt, speedup, book_value)
    {store(state, next), effects}
  end

  defp store(state, %__MODULE__{} = ship), do: State.put(state, "ships", ship.id, to_row(ship))
end
