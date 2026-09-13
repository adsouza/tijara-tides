defmodule TijaraTides.Localization.Names do
  use Gettext, backend: TijaraTides.Localization.Backend
  def translate("Agricultural machinery"), do: gettext("Agricultural machinery")
  def translate("Aluminium scrap"), do: gettext("Aluminium scrap")
  def translate("Appliances"), do: gettext("Appliances")
  def translate("Construction equipment"), do: gettext("Construction equipment")
  def translate("Copper scrap"), do: gettext("Copper scrap")
  def translate("Crude oil"), do: gettext("Crude oil")
  def translate("Designer clothing"), do: gettext("Designer clothing")
  def translate("Electronics"), do: gettext("Electronics")
  def translate("Everyday clothing"), do: gettext("Everyday clothing")
  def translate("Fruit"), do: gettext("Fruit")
  def translate("Grain"), do: gettext("Grain")
  def translate("Iron ore"), do: gettext("Iron ore")
  def translate("Jewelry"), do: gettext("Jewelry")
  def translate("Lumber"), do: gettext("Lumber")
  def translate("Meat"), do: gettext("Meat")
  def translate("Recovered plastics"), do: gettext("Recovered plastics")
  def translate("Refined fuel"), do: gettext("Refined fuel")
  def translate("Seafood"), do: gettext("Seafood")
  def translate("Spices"), do: gettext("Spices")
  def translate("Turbines"), do: gettext("Turbines")
  def translate("Vegetable oil"), do: gettext("Vegetable oil")
  def translate("Whisky"), do: gettext("Whisky")
  def translate("Balanced freighter"), do: gettext("Balanced freighter")
  def translate("Small freighter"), do: gettext("Small freighter")
  def translate("Bulk carrier"), do: gettext("Bulk carrier")
  def translate("Small refrigerated ship"), do: gettext("Small refrigerated ship")
  def translate("Small tanker"), do: gettext("Small tanker")
  def translate("sailing"), do: gettext("sailing")
  def translate("loading"), do: gettext("loading")
  def translate("unloading"), do: gettext("unloading")
  def translate("docked"), do: gettext("docked")
  def translate("berthed"), do: gettext("berthed")
  def translate("queued"), do: gettext("queued")
  def translate("waiting"), do: gettext("waiting")
  def translate("planned"), do: gettext("planned")
  def translate("completed"), do: gettext("completed")
  def translate("cancelled"), do: gettext("cancelled")
  def translate("paused"), do: gettext("paused")
  def translate("running"), do: gettext("running")
  def translate("draft"), do: gettext("draft")
  def translate("buy"), do: gettext("buy")
  def translate("sell"), do: gettext("sell")
  def translate("Buy"), do: gettext("Buy")
  def translate("Sell"), do: gettext("Sell")
  def translate("Queued"), do: gettext("Queued")
  def translate("Docked"), do: gettext("Docked")
  def translate("Berthed"), do: gettext("Berthed")
  def translate("Loading"), do: gettext("Loading")
  def translate("Unloading"), do: gettext("Unloading")
  def translate("Sailing"), do: gettext("Sailing")
  def translate("verified"), do: gettext("verified")
  def translate("pending"), do: gettext("pending")
  def translate("sent"), do: gettext("sent")
  def translate("failed"), do: gettext("failed")
  def translate("At anchorage"), do: gettext("At anchorage")
  def translate("Unknown company"), do: gettext("Unknown company")
  def translate("Unknown kind"), do: gettext("Unknown kind")
  def translate("Supply"), do: gettext("Supply")
  def translate("Demand"), do: gettext("Demand")
  def translate("Completing loading targets"), do: gettext("Completing loading targets")
  def translate("Waiting for a berth"), do: gettext("Waiting for a berth")
  def translate("Waiting for the limit price"), do: gettext("Waiting for the limit price")

  def translate("Waiting for cargo orders to be filled or cancelled"),
    do: gettext("Waiting for cargo orders to be filled or cancelled")

  def translate("Waiting for cargo handling to finish"),
    do: gettext("Waiting for cargo handling to finish")

  def translate("Waiting for available funds for fuel and canal fees"),
    do: gettext("Waiting for available funds for fuel and canal fees")

  def translate("Waiting for unpaid operating costs to clear"),
    do: gettext("Waiting for unpaid operating costs to clear")

  def translate("No sea route is available to the onward destination"),
    do: gettext("No sea route is available to the onward destination")

  def translate("The onward voyage exceeds the maximum duration"),
    do: gettext("The onward voyage exceeds the maximum duration")

  def translate("The onward destination is unavailable; update the visit plan"),
    do: gettext("The onward destination is unavailable; update the visit plan")

  def translate("Waiting for hold capacity; fill or cancel remaining orders"),
    do: gettext("Waiting for hold capacity; fill or cancel remaining orders")

  def translate("Hold capacity exhausted; cancelled unfilled remainder"),
    do: gettext("Hold capacity exhausted; cancelled unfilled remainder")

  def translate("Available demand exhausted; unsold cargo stays aboard"),
    do: gettext("Available demand exhausted; unsold cargo stays aboard")

  def translate("Maximum available purchase completed"),
    do: gettext("Maximum available purchase completed")

  def translate("Waiting for handling to finish"), do: gettext("Waiting for handling to finish")

  def translate("Choose one shared onward port for this visit before purchases can resume"),
    do: gettext("Choose one shared onward port for this visit before purchases can resume")

  def translate("Waiting for cargo aboard"), do: gettext("Waiting for cargo aboard")
  def translate("Waiting for market supply"), do: gettext("Waiting for market supply")

  def translate("Waiting for market demand or buyer funds"),
    do: gettext("Waiting for market demand or buyer funds")

  def translate("Waiting for available company funds or unpaid costs to clear"),
    do: gettext("Waiting for available company funds or unpaid costs to clear")

  def translate("Purchase spending cap exhausted"), do: gettext("Purchase spending cap exhausted")

  def translate("Waiting for funds after preserving onward voyage costs"),
    do: gettext("Waiting for funds after preserving onward voyage costs")

  def translate("Onward voyage is unavailable"), do: gettext("Onward voyage is unavailable")

  def translate("Cargo is currently unavailable for trading at this port"),
    do: gettext("Cargo is currently unavailable for trading at this port")

  def translate("Add stops and cargo targets, then start the route"),
    do: gettext("Add stops and cargo targets, then start the route")

  def translate("Following route"), do: gettext("Following route")

  def translate("Paused by player; committed handling continues"),
    do: gettext("Paused by player; committed handling continues")

  def translate("Completing sale targets"), do: gettext("Completing sale targets")

  def translate("Stopped after completing this visit"),
    do: gettext("Stopped after completing this visit")

  def translate("Route visit target"), do: gettext("Route visit target")

  def translate("Off route; return to the selected stop before resuming"),
    do: gettext("Off route; return to the selected stop before resuming")

  def translate("Awaiting arrival and a berth"), do: gettext("Awaiting arrival and a berth")
  def translate("Cancelled by player"), do: gettext("Cancelled by player")

  def translate("Cancelled remainder on departure"),
    do: gettext("Cancelled remainder on departure")

  def translate("Strait of Hormuz"), do: gettext("Strait of Hormuz")
  def translate("Northern Frangistan"), do: gettext("Northern Frangistan")
  def translate("Pearl River Delta"), do: gettext("Pearl River Delta")
  def translate(value), do: TijaraTides.Localization.Ports.translate(value)
end
