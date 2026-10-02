defmodule TijaraTides.Domain.Services.RouteEditing do
  @moduledoc "Coordinate ship route edits, linked demand and visit funding in one candidate."
  alias TijaraTides.Domain.{ShipWorld, WarehouseWorld}
  alias TijaraTides.Domain.Services.{LinkedOrders, DepartureFunding}

  def execute(state, account, command, context) do
    with {:ok, changed, reply} <- ShipWorld.edit_route(state, account, command, context),
         {:ok, changed} <-
           LinkedOrders.reconcile_edit(state, changed, account, command, context.catalogue),
         changed = release_removed_stops(state, changed, account, command),
         changed = DepartureFunding.settle_ships(state, changed, context.catalogue),
         {:ok, changed} <- fund_started_visit(changed, command) do
      {:ok, changed, reply}
    end
  end

  defp release_removed_stops(before, changed, account, %{"ship" => ship}) do
    kept = MapSet.new(ShipWorld.route_stops(changed, ship), & &1["id"])

    removed =
      for stop <- ShipWorld.route_stops(before, ship),
          not MapSet.member?(kept, stop["id"]),
          do: stop["id"]

    WarehouseWorld.release_stop_claims(changed, account["company_id"], removed)
  end

  defp fund_started_visit(state, %{"operation" => op, "ship" => ship})
       when op in ["start", "resume"],
       do: DepartureFunding.fund_current_visit(state, ship)

  defp fund_started_visit(state, _), do: {:ok, state}
end
