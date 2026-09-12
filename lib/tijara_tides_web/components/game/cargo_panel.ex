defmodule TijaraTidesWeb.GameUI.CargoPanel do
  @moduledoc "CargoPanel rendering; events remain owned by GameLive."
  use TijaraTidesWeb, :html
  import TijaraTidesWeb.GameUI.Presentation

  attr :cargo_filter_ship, :any, required: true
  attr :cargo_menu_open, :any, required: true
  attr :cargo_options, :any, required: true
  attr :cargo_roi_varies, :any, required: true
  attr :cargo_sort_roi, :any, required: true
  attr :definitions, :any, required: true
  attr :market_good, :any, required: true
  attr :market_sort, :any, required: true
  attr :ship, :any, required: true
  attr :view, :any, required: true

  def panel(assigns) do
    ~H"""
    <section id="cargo-panel" class="workspace-panel" aria-label="Cargo">
      <h2 class="panel-title">Cargo</h2>
      <div class="panel-content" tabindex="0" aria-label="Cargo markets">
        <section id="cargo-markets" class="my-6 rounded-xl border border-slate-700 p-5">
          <div class="space-y-3">
            <details
              id="cargo-market-help"
              phx-mounted={JS.ignore_attributes("open")}
              class="mb-3 text-sm text-slate-400"
            >
              <summary class="cursor-pointer">About cargo markets</summary>
              <p class="mt-2">
                Supply and demand in lots · prices per lot, before handling · updated live. Cargo choices show the highest available bid and lowest available ask; — means no market on that side. Select a port to inspect its market.
              </p>
            </details>
            <form
              :if={@ship}
              id="cargo-ship-filter"
              phx-change="cargo-filter-ship"
              class="mt-2 text-sm"
            >
              <label class="flex items-center gap-2">
                <input type="hidden" name="compatible" value="false" />
                <input
                  type="checkbox"
                  name="compatible"
                  value="true"
                  checked={@cargo_filter_ship}
                /> Show only cargo carried by {@definitions.classes[@ship["class"]]["name"]}
              </label>
            </form>
            <div
              id="cargo-market-selector"
              class="cargo-picker"
              phx-click-away="close-cargo-menu"
              phx-keydown="close-cargo-menu"
              phx-key="Escape"
            >
              <button
                id="market-good"
                type="button"
                phx-click="toggle-cargo-menu"
                aria-expanded={to_string(@cargo_menu_open)}
                aria-controls="cargo-options"
                class="cargo-choice rounded bg-slate-800 px-3 py-2"
              >
                <span>{if @market_good,
                  do: cargo_name(@market_good),
                  else: "No cargo markets available"}</span>
                <span class="cargo-spread">{if @market_good,
                  do: (List.keyfind(@cargo_options, @market_good, 0) |> elem(1)).label} ▾</span>
              </button>
              <div
                :if={@cargo_menu_open}
                id="cargo-options"
                class="cargo-options"
                role="group"
                aria-label="Choose cargo"
              >
                <div class="cargo-menu-row cargo-menu-heading px-3 py-2" aria-hidden="true">
                  <span>Cargo</span><span class="cargo-spread">Bid / ask</span><span class="cargo-roi">ROI</span>
                </div>
                <button
                  :for={{good, range} <- @cargo_options}
                  type="button"
                  phx-click="market-good"
                  phx-value-good={good}
                  aria-pressed={to_string(good == @market_good)}
                  class="cargo-choice cargo-menu-row px-3 py-2"
                >
                  <span>{cargo_name(good)}</span>
                  <span class="cargo-spread">{range.label}</span>
                  <span class="cargo-roi" aria-label={"ROI " <> cargo_roi(range.roi)}>{cargo_roi(
                    range.roi
                  )}</span>
                </button>
                <p :if={@cargo_options == []} class="p-3">No cargo markets available</p>
              </div>
            </div>
          </div>
          <form
            :if={@cargo_roi_varies}
            id="cargo-sort"
            phx-change="cargo-sort-roi"
            class="mt-2 flex items-start gap-3 text-sm"
          >
            <label class="flex shrink-0 items-center gap-2 whitespace-nowrap">
              <input type="hidden" name="roi" value="false" />
              <input type="checkbox" name="roi" value="true" checked={@cargo_sort_roi} /> Sort by ROI
            </label>
            <p class="text-xs leading-5 text-slate-400">
              Highest first: (best bid − best ask) ÷ best ask, before handling and voyage costs.
            </p>
          </form>
          <p class="mt-2 mb-2 text-xs text-slate-400">
            {if @ship && @ship["status"] == "docked",
              do: "Sea-route distances from #{@ship["port"]} in nautical miles.",
              else: "Select a docked ship to compare sea-route distances."}
          </p>
          <div class="cargo-comparison grid gap-2 md:grid-cols-2">
            <div
              :for={
                {side, heading, quantity_key, price_key} <- [
                  {"supply", "Supply", "stock", "ask"},
                  {"demand", "Demand", "demand", "bid"}
                ]
              }
              class="min-w-0 overflow-x-auto"
            >
              <% sort = @market_sort[side] %>
              <% rows = cargo_markets(@definitions, @view, @market_good, side, sort, @ship) %>
              <h3 class="mb-2 text-lg font-medium">{heading}</h3>
              <table
                id={"cargo-#{side}"}
                class="w-full text-sm"
                aria-label={heading <> " for selected cargo"}
              >
                <thead class="border-b border-slate-700 text-slate-400">
                  <tr>
                    <th
                      :for={
                        {column, label} <-
                          [
                            {"port", "Port"},
                            {quantity_key, if(side == "demand", do: "Lots", else: heading)},
                            {price_key, if(side == "supply", do: "Buy price", else: "Sell price")}
                          ] ++
                            if(side == "demand",
                              do: [{"distance", "nm"}],
                              else: []
                            )
                      }
                      scope="col"
                      class={
                        if column == "port",
                          do: "py-2 text-left",
                          else: "px-3 py-2 text-right"
                      }
                      aria-sort={
                        if elem(sort, 0) == column,
                          do: if(elem(sort, 1) == :asc, do: "ascending", else: "descending"),
                          else: "none"
                      }
                    >
                      <button
                        type="button"
                        phx-click="sort-markets"
                        phx-value-side={side}
                        phx-value-column={column}
                        class="whitespace-nowrap rounded hover:text-teal-300 focus-visible:outline-2 focus-visible:outline-teal-300"
                      >
                        {label}<span aria-hidden="true" class="ml-1">{if elem(sort, 0) ==
                                                                           column,
                                                                         do:
                                                                           if(
                                                                             elem(sort, 1) ==
                                                                               :asc,
                                                                             do: "↑",
                                                                             else: "↓"
                                                                           ),
                                                                         else: "↕"}</span>
                      </button>
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={quote <- rows}
                    data-port={quote["port"]}
                    class="border-b border-slate-800 last:border-0"
                  >
                    <th scope="row" class="py-2 text-left font-medium">
                      <button
                        type="button"
                        phx-click="port"
                        phx-value-id={quote["port"]}
                        class="text-teal-300 underline decoration-teal-800 underline-offset-4"
                      >{quote["port"]}</button>
                    </th>
                    <%= if quote["manual"] do %>
                      <td class="px-3 py-2 text-right tabular-nums">
                        {quote[quantity_key]}
                      </td>
                      <td class="px-3 py-2 text-right tabular-nums">
                        {if quote[quantity_key] > 0, do: money(quote[price_key]), else: "—"}
                      </td>
                    <% else %>
                      <td colspan="2" class="px-3 py-2 text-right text-slate-400">
                        Trading not available yet
                      </td>
                    <% end %>
                    <td :if={side == "demand"} class="text-right tabular-nums">
                      {if is_nil(quote["distance"]), do: "—", else: round(quote["distance"])}
                    </td>
                  </tr>
                  <tr :if={rows == []}>
                    <td
                      colspan={if(side == "demand", do: 4, else: 3)}
                      class="py-3 text-slate-400"
                    >
                      No ports for this cargo.
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </section>
      </div>
    </section>
    """
  end
end
