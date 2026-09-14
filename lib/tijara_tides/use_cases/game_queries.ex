defmodule TijaraTides.UseCases.GameQueries do
  @moduledoc "Authenticated snapshots and compatibility entry point for focused read-side queries."
  alias TijaraTides.Domain.{Fleet, CargoRules, Visibility}
  defdelegate compatible_cargo?(ship, item), to: CargoRules

  defdelegate auction_discovery(view, grouping \\ "status"),
    to: TijaraTides.UseCases.AuctionQueries

  defdelegate auction_options(definitions, view, port), to: TijaraTides.UseCases.AuctionQueries

  defdelegate exchange_options(definitions, view, port, selected),
    to: TijaraTides.UseCases.ExchangeQueries

  defdelegate warehouse_options(definitions, view, port, draft, ship),
    to: TijaraTides.UseCases.WarehouseQueries

  defdelegate route_editor(private, ship, catalogue), to: TijaraTides.UseCases.ShipPlanningQueries

  defdelegate instruction_editor(
                definitions,
                ship,
                draft,
                markets \\ %{},
                port \\ nil,
                company \\ nil
              ),
              to: TijaraTides.UseCases.ShipPlanningQueries

  defdelegate instruction_visits(private, ship_id), to: TijaraTides.UseCases.ShipPlanningQueries

  defdelegate instruction_onwards(private, ship_id, port),
    to: TijaraTides.UseCases.ShipPlanningQueries

  defdelegate destination_matrix(definitions, view, ship), to: TijaraTides.UseCases.MarketQueries

  defdelegate destination_options(definitions, view, ship, destination),
    to: TijaraTides.UseCases.MarketQueries

  defdelegate purchase_total(quote, ship, item, quantity), to: TijaraTides.UseCases.MarketQueries

  defdelegate trade_limits(view, ship, destination, catalogue),
    to: TijaraTides.UseCases.MarketQueries

  defdelegate purchase_voyage(ship, item, quantity, destination, fleet, clock, catalogue),
    to: TijaraTides.UseCases.MarketQueries

  defdelegate trade_freshness(quote, ship, side, good, quantity, clock),
    to: TijaraTides.UseCases.MarketQueries

  defdelegate route_distance(definitions, ship, destination),
    to: TijaraTides.UseCases.MarketQueries

  defdelegate cargo_markets(definitions, view, good, side, sort, ship),
    to: TijaraTides.UseCases.MarketQueries

  defdelegate manifest(cargo, catalogue), to: TijaraTides.UseCases.MarketQueries

  defdelegate visible_market_rows(definitions, view, ship, port),
    to: TijaraTides.UseCases.MarketQueries

  defdelegate available_to_trade(side, quote, ship, good), to: TijaraTides.UseCases.MarketQueries
  defdelegate cargo_aboard(ship, good), to: TijaraTides.UseCases.MarketQueries
  defdelegate sorted_manifest(cargo, goods, sort), to: TijaraTides.UseCases.MarketQueries

  defdelegate cargo_options(definitions, view, sort_roi, ship \\ nil),
    to: TijaraTides.UseCases.MarketQueries

  def ship_sale_value(ship, clock), do: Fleet.sale_value(ship, clock)

  def preview(game, catalogue, session, wall_ms, id, destination),
    do:
      preview(
        game,
        catalogue,
        TijaraTides.UseCases.Authentication.required(game, session, wall_ms),
        id,
        destination
      )

  def preview(game, catalogue, authenticated, id, destination) do
    with true <- is_binary(destination),
         {:ok, account} <- authenticated,
         %{"company_id" => owner} = ship <-
           TijaraTides.Domain.ReadState.get(game, "ships", id),
         true <- owner == account["company_id"] do
      quote =
        if ship["status"] == "sailing",
          do: Fleet.reroute_quote(ship, destination, game.clock_ms, catalogue),
          else:
            if(ship["status"] == "docked", do: Fleet.voyage_quote(ship, destination, catalogue))

      case quote do
        nil ->
          nil

        quote ->
          Map.put(
            quote,
            "freshness",
            CargoRules.voyage_freshness(ship, game.clock_ms, quote["duration_ms"])
          )
      end
    else
      _ -> nil
    end
  end

  def snapshot(game, catalogue, projection, session, wall_ms),
    do:
      snapshot(
        game,
        catalogue,
        projection,
        TijaraTides.UseCases.Authentication.required(game, session, wall_ms)
      )

  def snapshot(game, catalogue, projection, account) do
    private =
      case account do
        {:ok, account} ->
          private = Visibility.private(game, account)

          compatible =
            Map.new(private["ships"], fn {id, ship} ->
              {id,
               for(
                 {good, item} <- catalogue["goods"],
                 CargoRules.compatible_cargo?(ship, item),
                 do: good
               )}
            end)

          underway =
            Map.new(private["ships"], fn {id, ship} ->
              estimates =
                if ship["status"] == "sailing",
                  do:
                    CargoRules.voyage_freshness(
                      ship,
                      game.clock_ms,
                      max(0, ship["arrive_ms"] - game.clock_ms)
                    ),
                  else: []

              {id, estimates}
            end)

          private
          |> Map.put("compatible_cargo", compatible)
          |> Map.put("voyage_freshness", underway)

        _ ->
          nil
      end

    %{status: :ready, public: projection.public, private: private, markets: projection.markets}
  end
end
