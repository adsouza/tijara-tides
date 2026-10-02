defmodule TijaraTides.Domain.Trading do
  @moduledoc "Compatibility facade for the cross-aggregate trade settlement service."
  defdelegate pending_status(state, account, ship, catalogue),
    to: TijaraTides.Domain.Services.BerthAllocation

  defdelegate execute(state, account, trade, catalogue),
    to: TijaraTides.Domain.Services.TradeSettlement

  defdelegate purchase_total(quote, ship, item, quantity),
    to: TijaraTides.Domain.Services.TradeSettlement

  defdelegate purchased_cargo(quote, ship, item, quantity, clock, minimum, catalogue),
    to: TijaraTides.Domain.Services.TradeSettlement

  defdelegate purchase_limits(quote, ship, item, clock, minimum, catalogue),
    to: TijaraTides.Domain.Services.TradeSettlement

  defdelegate sale_capacity(quote), to: TijaraTides.Domain.PortCargoMarket
  defdelegate sale_proceeds(quote, quantity), to: TijaraTides.Domain.PortCargoMarket

  defdelegate purchasing_terms(company, budget, ship),
    to: TijaraTides.Domain.Services.TradeSettlement

  defdelegate purchase_shortfall(terms, total, required),
    to: TijaraTides.Domain.Services.TradeSettlement

  defdelegate current_budget(budgets, routes, stops, ship, port),
    to: TijaraTides.Domain.AutomationWorld

  defdelegate trade_admission(ship, side), to: TijaraTides.Domain.Ship

  defdelegate purchase_voyage(ship, item, quantity, destination, fleet, clock, catalogue),
    to: TijaraTides.Domain.Services.TradeSettlement

  defdelegate voyage_requirement(loaded, loading, destination, fleet, clock, catalogue),
    to: TijaraTides.Domain.Services.TradeSettlement
end
