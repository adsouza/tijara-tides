defmodule TijaraTides.Domain.ShipWorld do
  @moduledoc "Integrates ship transitions and automation with the shared atomic world."
  alias TijaraTides.Domain.{Ship, State}
  alias TijaraTides.Domain.Ship.{Rows, CargoRows}
  alias TijaraTides.Domain.CargoLots.Scope, as: Lots
  alias __MODULE__.{RoutePlans, VisitOrders}

  def fetch(state, id) do
    ship = Rows.decode(State.get(state, "ships", id))

    %{
      ship
      | route_plan: RoutePlans.load(state, id),
        visit_orders:
          State.entities(state, "ship_instructions")
          |> Map.values()
          |> Enum.filter(&(&1["ship_id"] == id))
          |> Enum.map(&Ship.VisitOrder.from_row/1),
        visit_plans:
          State.entities(state, "visit_plans")
          |> Map.values()
          |> Enum.filter(&(&1["ship_id"] == id))
          |> Enum.map(&Ship.VisitPlan.from_row/1)
    }
  end

  defdelegate pause_diverted_route(state, id), to: RoutePlans, as: :divert

  defdelegate edit_route(state, account, params, context), to: RoutePlans, as: :execute

  def route_stops(state, ship),
    do: RoutePlans.stops(state, ship) |> Enum.map(&Ship.RouteStop.to_row/1)

  defdelegate automation_enabled?(state, ship), to: RoutePlans, as: :executable?
  defdelegate prepare_visits(state, catalogue), to: RoutePlans, as: :advance
  defdelegate route_departed(state, ship, destination), to: RoutePlans, as: :departed

  defdelegate add_instruction(state, account, params, context),
    to: VisitOrders,
    as: :add

  defdelegate change_onward(state, account, ship, port, onward, catalogue, auto_depart),
    to: VisitOrders

  defdelegate cancel_instruction(state, account, id, catalogue),
    to: VisitOrders,
    as: :cancel

  defdelegate consume_departure(state, ship, destination, catalogue),
    to: VisitOrders,
    as: :depart

  defdelegate visit_onwards(state, ship, port), to: VisitOrders
  defdelegate wait_for_departure(state, id, reason), to: VisitOrders
  defdelegate wait_for_order(state, id, reason, catalogue), to: VisitOrders
  defdelegate cancel_visit_order(state, id, reason, catalogue), to: VisitOrders
  defdelegate complete_visit_order(state, id, reason, catalogue), to: VisitOrders
  defdelegate record_visit_fill(state, id, quantity, spent, catalogue), to: VisitOrders

  @automation ~w(route_rules route_stops ship_routes ship_instructions visit_plans)
  def cancel_automation(state, ship_id) do
    state = store(state, Ship.cancel_automation(fetch(state, ship_id)))

    Enum.reduce(@automation, state, fn kind, state ->
      Enum.reduce(State.entities(state, kind), state, fn {id, row}, state ->
        if row["ship_id"] == ship_id, do: State.delete(state, kind, id), else: state
      end)
    end)
  end

  def retire(state, id) do
    :retired = Ship.retire(fetch(state, id))
    state |> cancel_automation(id) |> State.delete("ships", id)
  end

  def commission(state, row) do
    if State.get(state, "ships", row["id"]), do: raise(ArgumentError, "Ship already exists")
    store(state, Ship.commission(Rows.decode(row)))
  end

  def load_cargo(state, id, cargo, cleaning, catalogue) do
    next =
      Ship.record_purchase(
        hull(state, id),
        Enum.map(cargo, &CargoRows.coerce/1),
        state.clock_ms,
        cleaning,
        catalogue
      )

    store(state, next)
  end

  def unload_cargo(state, id, good, quantity) do
    lots = %Lots{
      clock_ms: state.clock_ms,
      lot_allocation: Map.get(state, :lot_allocation, {:local, 1})
    }

    {lots, ship, sold} = Ship.record_sale(lots, hull(state, id), good, quantity)

    state =
      if lots.new_lots == [] do
        state
      else
        state
        |> Map.put(:lot_allocation, lots.lot_allocation)
        |> Map.update(:new_lots, lots.new_lots, &(&1 ++ lots.new_lots))
      end

    {store(state, ship), Enum.map(sold, &CargoRows.encode/1)}
  end

  def cargo_available(state, id, good), do: Ship.cargo_available(hull(state, id), good)

  def depart(state, id, destination, estimate, speedup),
    do:
      store(
        state,
        Ship.begin_voyage(hull(state, id), destination, estimate, state.clock_ms, speedup)
      )

  def reroute(state, id, destination, quote, paid),
    do: store(state, Ship.reroute(hull(state, id), destination, quote, paid, state.clock_ms))

  def advance_hull(state, id, elapsed, bankrupt, speedup, book_value) do
    {ship, effects} =
      Ship.advance(hull(state, id), state.clock_ms, elapsed, bankrupt, speedup, book_value)

    {store(state, ship), effects}
  end

  def request_berth(state, id) do
    ship = hull(state, id)
    next = Ship.request_berth(ship, state.clock_ms)
    if next == ship, do: state, else: store(state, next)
  end

  def grant_berth(state, id), do: store(state, Ship.grant_berth(hull(state, id), state.clock_ms))

  def admit_handling(state, id),
    do: store(state, Ship.admit_handling(hull(state, id), state.clock_ms))

  def release_berth(state, id, retry_at \\ nil),
    do: store(state, Ship.release_berth(hull(state, id), state.clock_ms, retry_at))

  def queue_trade(state, trade),
    do: store(state, Ship.queue_trade(hull(state, trade.ship_id), trade, state.clock_ms))

  def complete_pending_trade(state, id),
    do: store(state, Ship.complete_pending_trade(hull(state, id)))

  def cancel_pending_trade(state, id),
    do: store(state, Ship.cancel_pending_trade(hull(state, id)))

  defp hull(state, id), do: Rows.decode(State.get(state, "ships", id))
  defp store(state, %Ship{} = ship), do: State.put(state, "ships", ship.id, Rows.encode(ship))
end
