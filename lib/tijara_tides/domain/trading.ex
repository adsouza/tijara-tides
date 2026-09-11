defmodule TijaraTides.Domain.Trading do
  @moduledoc "Compatibility facade for the cross-aggregate trade settlement service."
  defdelegate execute(state, account, trade, catalogue),
    to: TijaraTides.Domain.Services.TradeSettlement

  defdelegate purchase_total(quote, ship, item, quantity),
    to: TijaraTides.Domain.Services.TradeSettlement

  defdelegate purchase_voyage(ship, item, quantity, destination, fleet, clock, catalogue),
    to: TijaraTides.Domain.Services.TradeSettlement
end
