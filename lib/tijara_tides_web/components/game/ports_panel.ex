defmodule TijaraTidesWeb.GameUI.PortsPanel do
  @moduledoc "PortsPanel rendering; events remain owned by GameLive."
  use TijaraTidesWeb, :html
  import TijaraTidesWeb.GameUI.Presentation
  alias TijaraTides.UseCases.GameQueries

  attr :definitions, :any, required: true
  attr :destination, :any, required: true
  attr :port_market_side, :any, required: true
  attr :preview, :any, required: true
  attr :purchase_good, :any, required: true
  attr :request_id, :any, required: true
  attr :selected_port, :any, required: true
  attr :ship, :any, required: true
  attr :trade_limits, :any, required: true
  attr :trade_quantities, :any, required: true
  attr :traffic_grouping, :any, required: true
  attr :view, :any, required: true

  def panel(assigns) do
    ~H"""
    <section id="ports-panel" class="workspace-panel" aria-label="Ports">
      <h2 class="panel-title">Ports</h2>
      <div class="panel-content" tabindex="0" aria-label="Port details and trading">
        <section class="my-6 rounded-xl border border-slate-700 p-5">
          <div class="flex flex-wrap gap-3">
            <form
              id="port-selector"
              phx-change="port"
              phx-hook="PortSelector"
              phx-update="ignore"
              data-selected={@selected_port}
            >
              <select
                aria-label="Inspect port"
                name="id"
                class="rounded bg-slate-800 px-3 py-2"
              ><option
                :for={name <- Enum.sort(Map.keys(@definitions.catalogue["ports"]))}
                value={name}
                selected={name == @selected_port}
              >
                {name}
              </option></select>
            </form>
          </div>
          <button
            :if={@ship && @ship["status"] == "docked" && @ship["port"] != @selected_port}
            id="set-port-destination"
            type="button"
            phx-click="port-destination"
            disabled={@destination == @selected_port}
            title={"Set #{@selected_port} as the destination for #{@ship["name"]}"}
            class="my-2 rounded border border-teal-700 px-3 py-2 text-sm text-teal-200 disabled:opacity-60"
          >
            {if @destination == @selected_port,
              do: "Selected destination",
              else: "Set as destination"}
          </button>
          <details
            id="about-port"
            phx-mounted={JS.ignore_attributes("open")}
            class="my-2 text-sm text-slate-400"
          >
            <summary class="cursor-pointer">About this port</summary>
            <p class="mt-2">
              {@definitions.catalogue["ports"][@selected_port]["identity"]}
            </p>
          </details>
          <section
            :if={@ship && @ship["status"] == "docked" && @ship["port"] != @selected_port}
            id="destination-planner"
            class="my-3 rounded border border-teal-900 p-2"
          >
            <% distance = route_distance(@definitions, @ship, @selected_port) %>
            <h3 class="text-sm text-teal-200">
              From {@ship["port"]} · {if distance,
                do: "#{round(distance)} nautical miles",
                else: "No route available"}
            </h3>
            <p class="my-2 text-xs text-slate-400">
              Cargo available at {@ship["port"]}. Profit estimates use the listed load, current prices, handling, cleaning, fuel, canals, and estimated fleet upkeep. Cash affordability and spoilage are not included; prices and demand can change.
            </p>
            <% options =
              GameQueries.destination_options(@definitions, @view, @ship, @selected_port) %>
            <p :if={options == []} class="text-sm text-slate-400">
              No compatible cargo available at the current port.
            </p>
            <table
              :if={options != []}
              class="w-full text-xs"
              aria-label="Destination trade opportunities"
            >
              <thead>
                <tr>
                  <th>Cargo / supply</th><th>Buy / lot</th><th>Bid / demand</th><th>
                    Load / est. profit
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={option <- options}
                  data-good={option.good}
                  class="border-t border-slate-700"
                >
                  <td>
                    <button
                      type="button"
                      phx-click="market-good"
                      phx-value-good={option.good}
                      class="text-left text-teal-300 underline"
                    >{cargo_name(option.good)}</button><p>
                      {option.source["stock"]} lots · {cargo_volume(
                        option.item,
                        option.source["stock"]
                      )}
                    </p>
                  </td>
                  <td>{money(option.source["ask"])}</td>
                  <td>
                    {if option.demand > 0,
                      do: "#{money(option.buyer["bid"])} / #{option.demand}",
                      else: "No demand"}
                  </td>
                  <td>
                    {option.lots} lots<p class={
                      if option.profit && option.profit >= 0,
                        do: "text-teal-300",
                        else: "text-red-400"
                    }>
                      {if is_nil(option.profit), do: "—", else: money(option.profit)}
                    </p>
                  </td>
                </tr>
              </tbody>
            </table>
          </section>
          <TijaraTidesWeb.PortTraffic.traffic
            public={@view.public}
            classes={@definitions.classes}
            port={@selected_port}
            grouping={@traffic_grouping}
          />
          <p class="mb-3 text-sm text-slate-400">
            Whole lots · finite local supply and demand · trades require your selected ship to be docked here. Handling takes time.
          </p>
          <div class="mb-3 flex gap-2" role="group" aria-label="Port market side">
            <button
              :for={{side, label} <- [{"buy", "Buy / supply"}, {"sell", "Sell / demand"}]}
              type="button"
              phx-click="port-market-side"
              phx-value-side={side}
              aria-pressed={to_string(@port_market_side == side)}
              class={[
                "flex-1 rounded px-3 py-2 text-sm",
                if(@port_market_side == side,
                  do: "bg-teal-800 text-teal-100",
                  else: "bg-slate-800 text-slate-400"
                )
              ]}
            >{label}</button>
          </div>
          <% market_rows =
            visible_market_rows(@definitions, @view, @ship, @selected_port)
            |> Enum.filter(fn {good, _} ->
              quote = @view.markets[@selected_port <> "|" <> good]
              quote[if(@port_market_side == "buy", do: "stock", else: "demand")] > 0
            end) %>
          <% show_ship_columns = owns_ship_at_port?(@view.private, @selected_port) %>
          <% selected_ship_here =
            @ship && @ship["port"] == @selected_port && @ship["status"] != "sailing" %>
          <% comparison_port =
            if @ship && @ship["status"] == "sailing",
              do: @ship["destination"],
              else: @destination %>
          <% compare_destination =
            @port_market_side == "buy" && @ship && is_binary(comparison_port) &&
              comparison_port != @selected_port &&
              @definitions.catalogue["ports"][comparison_port] %>
          <p
            :if={compare_destination}
            id="destination-market-note"
            class="mb-3 text-xs text-slate-400"
          >
            Destination bids: {comparison_port}. Gross profit excludes handling and voyage costs; demand and prices may change before arrival.
          </p>
          <% purchase =
            if @port_market_side == "buy" && selected_ship_here &&
                 @ship["status"] == "docked" do
              options =
                Enum.filter(market_rows, fn {good, item} ->
                  item["manual"] && Map.get(@trade_quantities, {"buy", good}, 0) > 0
                end)

              Enum.find(options, fn {good, _} -> good == @purchase_good end) ||
                List.first(options)
            end %>
          <%= if purchase do %>
            <% {good, item} = purchase %>
            <% quantity = Map.get(@trade_quantities, {"buy", good}, 0) %>
            <% voyage =
              GameQueries.purchase_voyage(
                @ship,
                item,
                quantity,
                @destination,
                @view.private["ships"],
                @view.public["clock_ms"],
                @definitions.catalogue
              ) %>
            <p
              :if={voyage}
              id="purchase-voyage-summary"
              class="mb-3 text-sm text-slate-300"
              role="status"
            >
              For {quantity} lots of {cargo_name(good)}, keep {money(voyage["required"])} for {@destination}: fuel {money(
                voyage["fuel"]
              )}, canals {money(voyage["canal_fees"])}, estimated fleet upkeep {money(
                voyage["upkeep"]
              )} through loading and arrival.
            </p>
          <% end %>
          <p
            :if={
              @port_market_side == "buy" && selected_ship_here &&
                @ship["status"] == "docked" && !@preview
            }
            id="purchase-destination-reminder"
            class="mb-3 text-sm text-amber-200"
          >
            Choose a destination port before buying.
          </p>
          <p :if={market_rows == []} class="py-4 text-slate-400">
            No cargo is available to {@port_market_side} here right now.
          </p>
          <div :if={market_rows != []} class="overflow-x-auto">
            <table
              id="port-market-table"
              class="w-full text-left text-sm"
              aria-label={if(@port_market_side == "buy", do: "Port supply", else: "Port demand")}
            >
              <thead class="text-slate-400">
                <tr>
                  <th class="cargo-description-column py-2">Cargo / lot size</th><th class="market-price-column">
                    {if @port_market_side == "buy",
                      do: "Buy / supply",
                      else: "Sell / demand"}
                  </th><th :if={show_ship_columns} class="aboard-column">
                    Aboard<br /><span class="font-normal">(lots)</span>
                  </th><th :if={show_ship_columns}>
                    Trade
                  </th>
                </tr>
              </thead><tbody>
                <tr
                  :for={{good, item} <- market_rows}
                  class="border-t border-slate-800"
                >
                  <% q = @view.markets[@selected_port <> "|" <> good] %>
                  <% destination_quote =
                    if compare_destination,
                      do: @view.markets[comparison_port <> "|" <> good] %>
                  <td class="cargo-description-column py-3">
                    <button
                      type="button"
                      phx-click="market-good"
                      phx-value-good={good}
                      aria-label={"View markets for #{cargo_name(good)}"}
                      class="rounded text-left text-teal-300 underline decoration-teal-700 underline-offset-2 hover:text-teal-100 focus-visible:outline-2 focus-visible:outline-teal-300"
                    >{cargo_name(good)}</button>
                    <p class="text-xs text-slate-400">
                      {item["weight_kg"]} kg · {cargo_volume(item, 1)}
                      <span :if={q["manual"]}> · handling {money(q["handling_fee"])} / lot</span>
                    </p>
                  </td>
                  <td class="market-price-column">
                    {money(q[if(@port_market_side == "buy", do: "ask", else: "bid")])} / {q[
                      if(@port_market_side == "buy", do: "stock", else: "demand")
                    ]}
                    <div
                      :if={
                        destination_quote && destination_quote["manual"] &&
                          destination_quote["demand"] > 0
                      }
                      class="destination-bid mt-1 text-xs"
                      data-good={good}
                    >
                      <span class="block text-slate-300">{money(destination_quote["bid"])} bid</span>
                      <span class={
                        if destination_quote["bid"] >= q["ask"],
                          do: "text-teal-300",
                          else: "text-red-400"
                      }>
                        {if destination_quote["bid"] > q["ask"], do: "+"}{money(
                          destination_quote["bid"] - q["ask"]
                        )} gross profit / lot
                      </span>
                      <% profit_lots =
                        if selected_ship_here,
                          do:
                            min(
                              Map.get(@trade_quantities, {"buy", good}, 0),
                              destination_quote["demand"]
                            ),
                          else: 0 %>
                      <span
                        :if={profit_lots > 0}
                        class={[
                          "destination-profit block",
                          if(destination_quote["bid"] >= q["ask"],
                            do: "text-teal-300",
                            else: "text-red-400"
                          )
                        ]}
                      >
                        {money((destination_quote["bid"] - q["ask"]) * profit_lots)} gross on {profit_lots} lots
                      </span>
                      <span class="block text-slate-400">{destination_quote["demand"]} lots demand</span>
                    </div>
                  </td>
                  <td
                    :if={show_ship_columns}
                    id={"aboard-#{String.replace(good, " ", "-")}"}
                    class="aboard-column font-semibold text-teal-200"
                  >
                    {if selected_ship_here, do: cargo_aboard(@ship, good), else: "—"}
                  </td>
                  <td :if={show_ship_columns}>
                    <span :if={!q["manual"]} class="text-slate-500">Available in a later market milestone</span>
                    <.form
                      :for={side <- [@port_market_side]}
                      :if={
                        q["manual"] && @ship && @ship["port"] == @selected_port &&
                          @ship["status"] == "docked"
                      }
                      for={%{}}
                      id={"trade-#{side}-#{String.replace(good, " ", "-")}"}
                      phx-submit="trade"
                      phx-change="trade-preview"
                      class="trade-controls flex flex-wrap gap-2"
                      phx-hook="TradeQuantity"
                      data-quantity={Map.get(@trade_quantities, {side, good}, 0)}
                      data-max={Map.get(@trade_limits, {side, good}, 0)}
                    >
                      <% available = Map.get(@trade_limits, {side, good}, 0) %>
                      <% quantity =
                        if available > 0,
                          do: Map.get(@trade_quantities, {side, good}, available),
                          else: 0 %>
                      <% freshness =
                        GameQueries.trade_freshness(
                          q,
                          @ship,
                          side,
                          good,
                          quantity,
                          @view.public["clock_ms"]
                        ) %>
                      <input type="hidden" name="request_id" value={@request_id} />
                      <input type="hidden" name="action" value={side} /><input
                        type="hidden"
                        name="good"
                        value={good}
                      /><input
                        type="hidden"
                        name="limit"
                        value={if(side == "buy", do: q["ask"], else: q["bid"])}
                      />
                      <input
                        type="range"
                        name="quantity_slider"
                        min={if available > 0, do: 1, else: 0}
                        max={available}
                        step="1"
                        value={quantity}
                        disabled={available < 1}
                        aria-label={"#{String.capitalize(side)} #{cargo_name(good)} quantity slider"}
                        class="w-full basis-full accent-teal-400"
                      />
                      <input
                        type="number"
                        id={"quantity-#{side}-#{String.replace(good, " ", "-")}"}
                        name="quantity"
                        min={if available > 0, do: 1, else: 0}
                        max={max(0, min(10_000, available))}
                        disabled={available <= 0}
                        value={quantity}
                        aria-label={"#{cargo_name(good)} quantity"}
                        class="w-16 rounded bg-slate-800 px-2"
                      />
                      <button
                        disabled={available <= 0}
                        title={
                          if available <= 0,
                            do:
                              if(side == "buy",
                                do:
                                  "No feasible purchase: check destination, funds, stock, and capacity",
                                else: "No feasible sale: check cargo, demand, and buyer funds"
                              )
                        }
                        class="rounded bg-teal-700 px-3 py-1 disabled:cursor-not-allowed disabled:bg-slate-700 disabled:text-slate-400 disabled:opacity-60"
                      >{String.capitalize(side)}</button>
                      <%= if side == "buy" and available > 0 and quantity > 0 do %>
                        <% total = GameQueries.purchase_total(q, @ship, item, quantity) %>
                        <% voyage =
                          GameQueries.purchase_voyage(
                            @ship,
                            item,
                            quantity,
                            @destination,
                            @view.private["ships"],
                            @view.public["clock_ms"],
                            @definitions.catalogue
                          ) %>
                        <% unaffordable =
                          is_nil(voyage) or
                            total + voyage["required"] >
                              @view.private["company"]["cash"] -
                                @view.private["company"]["reserved"] or
                            @view.private["company"]["unpaid"] > 0 %>
                        <span
                          class={[
                            "purchase-total self-center whitespace-nowrap text-sm tabular-nums",
                            if(unaffordable, do: "text-red-400", else: "text-slate-300")
                          ]}
                          title={
                            if unaffordable,
                              do:
                                "Choose a valid destination and leave enough cash for fuel, canal fees, and estimated fleet upkeep after purchasing. Includes handling and any tanker cleaning fee.",
                              else: "Includes handling and any tanker cleaning fee."
                          }
                          role="status"
                        >
                          {money(total)} total<span :if={unaffordable} class="sr-only"> — insufficient available funds</span>
                        </span>
                      <% end %>
                      <p
                        :if={freshness && available > 0}
                        class="w-full text-xs text-amber-200"
                        role="status"
                      >
                        {quantity} lots: first expiry in {minutes(freshness["remaining_ms"])} min now;
                        estimated {minutes(freshness["after_ms"])} min remaining after {minutes(
                          freshness["handling_ms"]
                        )} min handling.
                        <strong :if={freshness["after_ms"] == 0}>Expected to expire during handling.</strong>
                        Estimates may change before settlement.
                      </p>
                    </.form>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </section>
    """
  end
end
