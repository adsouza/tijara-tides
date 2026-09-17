defmodule TijaraTides.Domain.Trading do
  @moduledoc "Compatibility facade for the cross-aggregate trade settlement service."
  defdelegate pending_status(state, account, ship, catalogue),
    to: TijaraTides.Domain.Services.BerthAllocation

  defdelegate execute(state, account, trade, catalogue),
    to: TijaraTides.Domain.Services.TradeSettlement

  defdelegate purchase_total(quote, ship, item, quantity),
    to: TijaraTides.Domain.Services.TradeSettlement

  defdelegate purchase_voyage(ship, item, quantity, destination, fleet, clock, catalogue),
    to: TijaraTides.Domain.Services.TradeSettlement
end
