defmodule TijaraTides.Domain.Services.RemoteOrderSettlement do
  @moduledoc "Linked-order settlement eligibility, exclusive claims and cancellation effects."
  alias TijaraTides.Domain.{State, WarehouseWorld, AutomationWorld}

  def fill_allowed?(state, order) do
    link =
      Enum.find_value(State.entities(state, "remote_links"), fn {_, link} ->
        if link["order_id"] == order.id, do: link
      end)

    if link do
      route = State.get(state, "ship_routes", link["ship_id"])
      stop = State.get(state, "route_stops", link["stop_id"])
      ship = State.get(state, "ships", link["ship_id"])

      current =
        route && stop && route["cursor"] == stop["position"] && not route["visit_finished"]

      link["status"] == "active" && ship && stop &&
        not (current &&
               ((route["wait_deadline_ms"] != nil && route["wait_deadline_ms"] <= state.clock_ms) ||
                  ship["berth_granted_ms"] != nil))
    else
      true
    end
  end

  def record_fill(state, order, quantity, catalogue) do
    link =
      Enum.find_value(State.entities(state, "remote_links"), fn {_, link} ->
        if(link["order_id"] == order.id, do: link)
      end)

    if link do
      unless link["status"] == "active",
        do: raise(ArgumentError, "A handed-over remote order cannot fill")

      state
      |> WarehouseWorld.earmark_remote_fill(link, order, quantity, catalogue)
      |> AutomationWorld.record_remote_fill(link, quantity)
    else
      state
    end
  end

  def order_cancelled(state, order_id) do
    Enum.reduce(State.entities(state, "remote_links"), state, fn {_, link}, s ->
      if link["order_id"] == order_id && link["status"] == "active",
        do: AutomationWorld.close_link(s, link, "expired"),
        else: s
    end)
  end
end
