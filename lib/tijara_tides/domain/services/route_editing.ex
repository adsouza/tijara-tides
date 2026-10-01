defmodule TijaraTides.Domain.Services.RouteEditing do
  @moduledoc "Coordinate ship route edits, linked demand and visit funding in one candidate."
  alias TijaraTides.Domain.ShipWorld
  alias TijaraTides.Domain.Services.{LinkedOrders, DepartureFunding}

  def execute(state, account, command, context) do
    with {:ok, changed, reply} <- ShipWorld.edit_route(state, account, command, context),
         {:ok, changed} <-
           LinkedOrders.reconcile_edit(state, changed, account, command, context.catalogue),
         {:ok, changed} <- fund_started_visit(changed, command) do
      {:ok, DepartureFunding.reconcile(changed, context.catalogue), reply}
    end
  end

  defp fund_started_visit(state, %{"operation" => op, "ship" => ship})
       when op in ["start", "resume"],
       do: DepartureFunding.fund_current_visit(state, ship)

  defp fund_started_visit(state, _), do: {:ok, state}
end
