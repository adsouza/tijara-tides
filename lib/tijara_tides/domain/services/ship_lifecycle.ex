defmodule TijaraTides.Domain.Services.ShipLifecycle do
  @moduledoc "Coordinate ship admission and disposal with linked orders and funding reservations."
  alias TijaraTides.Domain.{Ship, ShipWorld, AutomationWorld, WarehouseWorld}
  alias TijaraTides.Domain.Services.LinkedOrders

  def cancel_automation(state, ship),
    do:
      state
      |> AutomationWorld.release_ship(ship)
      |> LinkedOrders.remove_ship(ship)
      |> ShipWorld.cancel_automation(ship)

  def retire(state, ship) do
    :retired = Ship.retire(ShipWorld.fetch(state, ship))
    state |> cancel_automation(ship) |> ShipWorld.retire(ship)
  end

  def acquire(state, ship, company, price),
    do: state |> cancel_automation(ship) |> ShipWorld.acquire(ship, company, price)

  def grant_berth(state, ship),
    do: state |> LinkedOrders.handover(ship) |> ShipWorld.grant_berth(ship)

  def admit_handling(state, ship),
    do: state |> LinkedOrders.handover(ship) |> ShipWorld.admit_handling(ship)

  def transfer_warehouse(state, account, command, catalogue, admission \\ :normal) do
    with {:ok, changed, reply} <-
           WarehouseWorld.transfer(state, account, command, catalogue, admission) do
      {:ok, LinkedOrders.handover(changed, command["ship"]), reply}
    end
  end
end
