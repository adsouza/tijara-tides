defmodule TijaraTides.Domain.ShipRoutes do
  @moduledoc "Compatibility facade. New commands enter through Ship."
  defdelegate execute(state, account, params, context),
    to: TijaraTides.Domain.Ship,
    as: :edit_route

  defdelegate stops(state, ship), to: TijaraTides.Domain.Ship, as: :route_stops
  defdelegate executable?(state, ship), to: TijaraTides.Domain.Ship, as: :automation_enabled?
  defdelegate advance(state, catalogue), to: TijaraTides.Domain.Ship, as: :prepare_visits
  defdelegate departed(state, ship, destination), to: TijaraTides.Domain.Ship, as: :route_departed
end
