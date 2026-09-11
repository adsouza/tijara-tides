defmodule TijaraTides.Domain.ShipInstructions do
  @moduledoc "Compatibility facade. New visit operations enter through Ship."
  defdelegate add(state, account, params, context),
    to: TijaraTides.Domain.Ship,
    as: :add_instruction

  def change_onward(state, account, ship, port, onward, catalogue, auto_depart \\ nil),
    do:
      TijaraTides.Domain.Ship.change_onward(
        state,
        account,
        ship,
        port,
        onward,
        catalogue,
        auto_depart
      )

  defdelegate cancel(state, account, id, catalogue),
    to: TijaraTides.Domain.Ship,
    as: :cancel_instruction

  defdelegate depart(state, ship, destination, catalogue),
    to: TijaraTides.Domain.Ship,
    as: :consume_departure

  defdelegate advance(state, catalogue), to: TijaraTides.Domain.Ship, as: :execute_visits
end
