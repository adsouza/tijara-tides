defmodule TijaraTides.Domain.ShipRoutes do
  @moduledoc "Compatibility facade. New commands enter through Ship."
  defdelegate execute(state, account, params, context),
    to: TijaraTides.Domain.ShipWorld,
    as: :edit_route

  defdelegate stops(state, ship), to: TijaraTides.Domain.ShipWorld, as: :route_stops
  defdelegate executable?(state, ship), to: TijaraTides.Domain.ShipWorld, as: :automation_enabled?
  defdelegate advance(state, catalogue), to: TijaraTides.Domain.ShipWorld, as: :prepare_visits

  defdelegate departed(state, ship, destination),
    to: TijaraTides.Domain.ShipWorld,
    as: :route_departed
end
