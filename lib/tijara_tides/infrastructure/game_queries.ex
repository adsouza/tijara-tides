defmodule TijaraTides.Infrastructure.GameQueries do
  @moduledoc "Read API adapter supplying the loaded catalogue to pure application queries."
  alias TijaraTides.UseCases.GameQueries, as: Queries
  alias TijaraTides.Infrastructure.GameCatalogue

  defdelegate ship_sale_value(ship, clock), to: Queries

  defdelegate compatible_cargo?(ship, item), to: Queries

  defdelegate destination_options(definitions, view, ship, destination), to: Queries
  defdelegate purchase_total(quote, ship, item, quantity), to: Queries
  defdelegate trade_freshness(quote, ship, side, good, quantity, clock), to: Queries

  def trade_limits(view, ship, destination),
    do: Queries.trade_limits(view, ship, destination, GameCatalogue.all())

  def purchase_voyage(ship, item, quantity, destination, fleet, clock),
    do:
      Queries.purchase_voyage(
        ship,
        item,
        quantity,
        destination,
        fleet,
        clock,
        GameCatalogue.all()
      )

  defdelegate route_distance(definitions, ship, destination), to: Queries
  defdelegate cargo_markets(definitions, view, good, side, sort, ship), to: Queries
  def manifest(cargo), do: Queries.manifest(cargo, GameCatalogue.all())
  defdelegate instruction_editor(definitions, ship, draft), to: Queries
  defdelegate instruction_visits(private, ship_id), to: Queries
  defdelegate instruction_onwards(private, ship_id, port), to: Queries
  defdelegate cargo_options(definitions, view, sort_roi), to: Queries
  defdelegate cargo_options(definitions, view, sort_roi, ship), to: Queries
  defdelegate visible_market_rows(definitions, view, ship, port), to: Queries
  defdelegate available_to_trade(side, quote, ship, good), to: Queries
  defdelegate cargo_aboard(ship, good), to: Queries
  defdelegate sorted_manifest(cargo, goods, sort), to: Queries
end
