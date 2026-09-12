defmodule TijaraTidesWeb.GameUI.FleetPanel do
  @moduledoc "FleetPanel rendering; events remain owned by GameLive."
  use TijaraTidesWeb, :html
  import TijaraTidesWeb.GameUI.Presentation
  alias TijaraTides.UseCases.GameQueries

  attr :definitions, :any, required: true
  attr :destination, :any, required: true
  attr :fleet_status, :any, required: true
  attr :inspected_ship, :any, required: true
  attr :instruction_drafts, :any, required: true
  attr :manifest_sort, :any, required: true
  attr :map_filters_open, :any, required: true
  attr :map_region, :any, required: true
  attr :map_ship_classes, :any, required: true
  attr :map_ships, :any, required: true
  attr :map_show_others, :any, required: true
  attr :preview, :any, required: true
  attr :request_id, :any, required: true
  attr :route_drafts, :any, required: true
  attr :selected_port, :any, required: true
  attr :selected_ship, :any, required: true
  attr :ship, :any, required: true
  attr :view, :any, required: true

  def panel(assigns) do
    ~H"""
    <section id="ships-panel" class="workspace-panel" aria-label="Ships">
      <h2 class="panel-title">Ships</h2>
      <TijaraTidesWeb.GameUI.MapPanel.panel
        definitions={@definitions}
        inspected_ship={@inspected_ship}
        map_filters_open={@map_filters_open}
        map_region={@map_region}
        map_ship_classes={@map_ship_classes}
        map_ships={@map_ships}
        map_show_others={@map_show_others}
        selected_port={@selected_port}
        view={@view}
      />
      <div class="panel-content" tabindex="0" aria-label="Fleet and ship details">
        <section
          :if={
            @inspected_ship && @view.public["ships"][@inspected_ship] &&
              !(@view.private && @view.private["ships"][@inspected_ship])
          }
          id="public-ship-inspector"
          class="my-6 rounded-xl border border-slate-700 p-5"
        >
          <% inspected = @view.public["ships"][@inspected_ship] %>
          <div class="rounded-xl border border-slate-700 bg-slate-900/70 p-4">
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <h2 class="break-words text-lg font-semibold text-teal-200">
                  {inspected["name"]}
                </h2>
                <p class="mt-1 text-sm text-slate-400">
                  {@view.public["companies"][inspected["company_id"]]["name"]}
                </p>
              </div>
              <button
                type="button"
                phx-click="close-map-ship"
                aria-label="Dismiss ship information"
                class="shrink-0 rounded px-2 py-1 text-slate-400 hover:bg-slate-800 hover:text-white"
              >✕</button>
            </div>
            <div class="mt-3 flex flex-wrap items-center gap-2 text-xs">
              <span class="rounded-full border border-slate-600 px-2 py-1 text-slate-300">{@definitions.classes[
                inspected["class"]
              ]["name"]}</span>
              <span
                :if={inspected["status"] != "sailing"}
                class="rounded-full bg-teal-950 px-2 py-1 capitalize text-teal-200"
              >{inspected[
                "status"
              ]}</span>
            </div>
            <p
              :if={@view.public["companies"][inspected["company_id"]]["bankruptcy_ms"] != nil}
              class="mt-3 rounded border border-red-900 bg-red-950/40 p-2 text-sm text-red-300"
            >
              Company in bankruptcy — assets in receivership
            </p>
            <div class="mt-3 border-t border-slate-700 pt-3">
              <p class="mb-1 text-xs text-slate-400">
                {if inspected["destination"], do: "Route", else: "Port"}
              </p>
              <p class="flex flex-wrap items-center gap-2 text-sm font-medium">
                <span>{inspected["port"]}</span>
                <span :if={inspected["destination"]} aria-label="to" class="text-teal-400">→</span>
                <span :if={inspected["destination"]}>{inspected["destination"]}</span>
              </p>
            </div>
          </div>
        </section>
        <section :if={@view.private && @view.private["company"]} class="my-6">
          <h2 class="mb-3 text-xl font-semibold">Your fleet</h2>
          <details
            id="shipyard"
            phx-mounted={JS.ignore_attributes("open")}
            open={map_size(@view.private["ships"]) == 0}
            class="mb-3 rounded border border-slate-600 p-3"
          >
            <summary class="cursor-pointer">Buy a ship at {@selected_port}</summary>
            <p class="my-2 text-sm">
              Choose a port in the Ports panel to buy there. Ships arrive immediately, empty and docked. Keep cash for cargo, fuel and crew.
            </p>
            <button
              type="button"
              phx-click={
                JS.set_attribute({"open", ""}, to: "#company-menu")
                |> JS.push("report-close")
              }
              class="mb-2 rounded border border-teal-600 px-3 py-1"
            >Arrange a loan</button>
            <.form
              :for={{class, spec} <- Enum.sort(@definitions.classes)}
              for={%{}}
              id={"shipyard-" <> class}
              phx-submit="purchase-ship"
              class="my-2 flex flex-wrap items-center justify-between gap-2"
            >
              <input type="hidden" name="request_id" value={@request_id} />
              <input type="hidden" name="class" value={class} />
              <input type="hidden" name="price_limit" value={spec["price"]} />
              <span>{spec["name"]} · {money(spec["price"])}<br /><small>{div(
                spec["weight"],
                1000
              )} tonnes · {div(spec["volume"], 1000)} m³ capacity</small></span>
              <button
                disabled={
                  spec["price"] >
                    @view.private["company"]["cash"] - @view.private["company"]["reserved"]
                }
                phx-disable-with="Buying…"
                class="rounded bg-teal-700 px-3 py-1 disabled:opacity-40"
              >Buy ship</button>
            </.form>
          </details>

          <form id="fleet-filter" phx-change="fleet-status" class="mb-3 text-sm">
            <label for="fleet-status">Ship status</label>
            <select
              id="fleet-status"
              name="status"
              class="ml-2 rounded bg-slate-800 px-2 py-1"
            >
              <option
                :for={
                  {value, label} <- [
                    {"all", "All ships"},
                    {"docked", "Docked"},
                    {"loading", "Loading"},
                    {"unloading", "Unloading"},
                    {"sailing", "Sailing"}
                  ]
                }
                value={value}
                selected={@fleet_status == value}
              >
                {label}
              </option>
            </select>
          </form>
          <p
            :if={
              !Enum.any?(@view.private["ships"], fn {_, s} ->
                @fleet_status == "all" || s["status"] == @fleet_status
              end)
            }
            class="mb-3 text-sm text-slate-400"
          >
            No ships with this status.
          </p>
          <div class="fleet-list">
            <button
              :for={{id, s} <- Enum.sort(@view.private["ships"])}
              :if={@fleet_status == "all" || s["status"] == @fleet_status}
              phx-click="ship"
              phx-value-id={id}
              aria-pressed={if id == @selected_ship, do: "true", else: "false"}
              class={[
                "min-w-0 rounded-xl border p-3 text-left break-words",
                if(id == @selected_ship,
                  do: "border-teal-400 bg-slate-800",
                  else: "border-slate-700"
                )
              ]}
            >
              <strong>{s["name"]}</strong><p>
                {@definitions.classes[s["class"]]["name"]} · {s["status"]}
              </p><p>
                {s["port"]}<span :if={s["destination"]}> → {s["destination"]}</span>
              </p>
              <p :if={s["arrive_ms"]} class="text-teal-300">
                {minutes(max(0, s["arrive_ms"] - @view.public["clock_ms"]))} min remaining
              </p>
            </button>
          </div>
          <div :if={@ship} class="mt-4 rounded-xl bg-slate-900 p-5">
            <% ship_value =
              GameQueries.ship_sale_value(
                @ship,
                @view.public["clock_ms"]
              ) %>
            <p class="text-sm">
              Book value: {finance_money(ship_value.book)}
              <span class="ml-2 text-xs text-slate-400">Depreciates over 28 active-world days to 20% of build value.</span>
            </p>
            <details
              :if={@ship["status"] != "sailing"}
              id={"shipyard-offer-" <> @ship["id"]}
              phx-mounted={JS.ignore_attributes("open")}
              class="my-2"
            >
              <summary class="cursor-pointer">Shipyard offer</summary>
              <.form
                :if={@ship["status"] == "docked" && @ship["cargo"] == []}
                for={%{}}
                id="sell-ship-form"
                phx-submit="sell-ship"
                class="my-2 flex items-center gap-3"
              >
                <input type="hidden" name="request_id" value={@request_id} />
                <input type="hidden" name="ship" value={@ship["id"]} />
                <input type="hidden" name="minimum" value={ship_value.proceeds} />
                <button
                  type="submit"
                  class="rounded border px-3 py-1"
                  phx-disable-with="Selling…"
                  data-confirm="Sell this ship to the shipyard? The ship will leave your fleet."
                >Sell ship for {finance_money(ship_value.proceeds)}</button>
                <span class="text-xs text-slate-400">90% of book value.</span>
              </.form>
            </details>
            <h3 class="mt-4 mb-2 text-lg font-semibold">{@ship["name"]} — Manifest</h3>
            <% occupied =
              Enum.reduce(@ship["cargo"], %{weight: 0, volume: 0}, fn batch, used ->
                good = @definitions.catalogue["goods"][batch["good"]]

                %{
                  weight: used.weight + batch["quantity"] * good["weight_kg"],
                  volume: used.volume + batch["quantity"] * good["volume_l"]
                }
              end) %>
            <p id="ship-capacity" class="text-sm text-slate-400 tabular-nums">
              Capacity used: {occupied.weight} / {@definitions.classes[@ship["class"]][
                "weight"
              ]} kg · {cubic_meters(occupied.volume)} / {cubic_meters(
                @definitions.classes[@ship["class"]]["volume"]
              )}
            </p>
            <p :if={@ship["cargo"] == []} class="mt-2 text-slate-400">Empty hold</p>
            <div :if={@ship["cargo"] != []} class="mt-3 overflow-x-auto">
              <table class="w-full text-sm" aria-label="Ship cargo manifest">
                <thead class="border-b border-slate-700 text-slate-400">
                  <tr>
                    <th
                      :for={
                        {column, label} <- [
                          {"good", "Cargo"},
                          {"quantity", "Lots"},
                          {"weight", "Weight"},
                          {"volume", "Volume"},
                          {"average_cost", "Avg. cost"},
                          {"expires_ms", "First expiry"}
                        ]
                      }
                      scope="col"
                      aria-sort={
                        if elem(@manifest_sort, 0) == column,
                          do:
                            if(elem(@manifest_sort, 1) == :asc,
                              do: "ascending",
                              else: "descending"
                            ),
                          else: "none"
                      }
                      class={
                        if column == "good",
                          do: "py-2 pr-4 text-left",
                          else: "px-4 py-2 text-right"
                      }
                    >
                      <button
                        type="button"
                        phx-click="sort-manifest"
                        phx-value-column={column}
                        class="whitespace-nowrap rounded hover:text-teal-300 focus-visible:outline-2 focus-visible:outline-teal-300"
                      >
                        {label}<span aria-hidden="true" class="ml-1">{if elem(
                                                                           @manifest_sort,
                                                                           0
                                                                         ) ==
                                                                           column,
                                                                         do:
                                                                           if(
                                                                             elem(
                                                                               @manifest_sort,
                                                                               1
                                                                             ) ==
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
                    :for={
                      b <-
                        sorted_manifest(
                          @ship["cargo"],
                          @definitions.catalogue["goods"],
                          @manifest_sort
                        )
                    }
                    id={"manifest-#{String.replace(b["good"], " ", "-")}"}
                    class="border-b border-slate-800 last:border-0"
                  >
                    <th scope="row" class="py-3 pr-4 text-left font-medium">
                      <button
                        type="button"
                        phx-click="market-good"
                        phx-value-good={b["good"]}
                        aria-label={"View markets for #{cargo_name(b["good"])}"}
                        class="rounded text-left text-teal-300 underline decoration-teal-700 underline-offset-2 hover:text-teal-100 focus-visible:outline-2 focus-visible:outline-teal-300"
                      >{cargo_name(b["good"])}</button>
                    </th>
                    <td class="px-4 py-3 text-right tabular-nums">{b["quantity"]}</td>
                    <td class="whitespace-nowrap px-4 py-3 text-right tabular-nums">
                      {b["quantity"] *
                        @definitions.catalogue["goods"][b["good"]]["weight_kg"]} kg
                    </td>
                    <td class="whitespace-nowrap px-4 py-3 text-right tabular-nums">
                      {cargo_volume(
                        @definitions.catalogue["goods"][b["good"]],
                        b["quantity"]
                      )}
                    </td>
                    <td class="whitespace-nowrap px-4 py-3 text-right tabular-nums">
                      {money(b["average_cost"])}
                    </td>
                    <td class="whitespace-nowrap py-3 pl-4 text-right tabular-nums">
                      <%= if b["expires_ms"] do %>
                        {div(max(0, b["expires_ms"] - @view.public["clock_ms"]), 60_000)} min
                      <% else %>
                        <span aria-label="Does not expire">—</span>
                      <% end %>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <.form
              :if={@ship["status"] == "docked"}
              for={%{}}
              id="voyage-preview"
              phx-submit="preview"
              phx-change="preview"
              class="mt-4 flex gap-3"
            >
              <select
                name="destination"
                aria-label="Destination"
                class="rounded bg-slate-800 px-3 py-2"
              ><option value="" selected={is_nil(@destination) or @destination == ""}>
                Choose a destination before buying
              </option><option
                :for={
                  name <-
                    Enum.sort(Map.keys(@definitions.catalogue["ports"])) -- [@ship["port"]]
                }
                value={name}
                selected={name == @destination}
              >
                {name}
              </option></select>
            </.form>
            <div :if={@preview} class="mt-3 flex flex-wrap items-center gap-3">
              <span>{minutes(@preview["duration_ms"])} min · fuel {money(@preview["fuel"])} · estimated crew {money(
                @preview["crew_estimate"]
              )} · canals {money(@preview["canal_fees"])}</span><button
                phx-click="sail"
                phx-value-request_id={@request_id}
                class="rounded bg-teal-600 px-4 py-2"
              >Reserve fuel and sail</button>
              <.voyage_freshness
                id={"preview-freshness-" <> @ship["id"]}
                estimates={@preview["freshness"]}
              />
            </div>
            <.voyage_freshness
              id={"voyage-freshness-" <> @ship["id"]}
              estimates={@view.private["voyage_freshness"][@ship["id"]]}
            />
            <TijaraTidesWeb.ShipRouteEditor.panel
              ship={@ship}
              model={GameQueries.route_editor(@view.private, @ship, @definitions.catalogue)}
              catalogue={@definitions.catalogue}
              drafts={@route_drafts}
              request_id={@request_id}
            />
            <details
              :if={
                instruction_port(@ship, @destination, @definitions) != nil &&
                  is_nil((@view.private["ship_routes"] || %{})[@ship["id"]])
              }
              id={"instructions-" <> @ship["id"]}
              phx-mounted={JS.ignore_attributes("open")}
              class="mt-4 rounded border border-slate-700 p-3"
            >
              <summary class="cursor-pointer font-semibold">
                Next port cargo instructions
              </summary>
              <p class="my-2 text-sm text-slate-400">
                Execute when berthed. Sales unload before purchases load. Partial fills retry while waiting; sailing cancels any remainder. Prices are per lot, excluding handling. A purchase cap includes all purchase costs and does not reserve cash.
              </p>
              <% visit_port = instruction_port(@ship, @destination, @definitions) %>
              <% instruction =
                GameQueries.instruction_editor(
                  @definitions,
                  @ship,
                  Map.get(@instruction_drafts, @ship["id"], %{}),
                  @view.markets,
                  visit_port,
                  @view.private["company"]
                ) %>
              <% duplicate_sell =
                instruction.side == "sell" &&
                  Enum.any?(@view.private["ship_instructions"], fn {_, order} ->
                    order["ship_id"] == @ship["id"] && order["good"] == instruction.good &&
                      order["side"] == "sell" && order["status"] in ["planned", "waiting"]
                  end) %>

              <% visits = GameQueries.instruction_visits(@view.private, @ship["id"]) %>
              <% visits =
                if visit_port, do: Map.put_new(visits, visit_port, []), else: visits %>
              <% onwards =
                GameQueries.instruction_onwards(@view.private, @ship["id"], visit_port) %>

              <p :if={is_nil(visit_port)} class="my-3 text-sm text-amber-200">
                Choose a destination in the voyage controls before adding instructions.
              </p>
              <.form
                :if={visit_port != nil}
                for={%{}}
                id={"instruction-form-" <> @ship["id"]}
                phx-submit="add-instruction"
                phx-change="edit-instruction"
                class="grid grid-cols-2 gap-2 text-sm"
              >
                <input type="hidden" name="request_id" value={@request_id} />
                <p class="col-span-2 font-semibold">Instructions at {visit_port}</p>
                <label>
                  Action
                  <select
                    name="side"
                    aria-label="Instruction action"
                    class="block w-full rounded bg-slate-800 p-2"
                  ><option
                    value="sell"
                    selected={
                      instruction_value(@instruction_drafts, @ship, "side", "sell") ==
                        "sell"
                    }
                  >
                    Sell
                  </option><option
                    value="buy"
                    selected={instruction_value(@instruction_drafts, @ship, "side", "sell") == "buy"}
                  >
                    Buy
                  </option></select>
                </label>
                <label>
                  Cargo
                  <select
                    name="good"
                    aria-label="Instruction cargo"
                    disabled={instruction.goods == []}
                    class="block w-full rounded bg-slate-800 p-2"
                  >
                    <option :if={instruction.goods == []} value="">
                      No cargo available
                    </option>
                    <option
                      :for={{good, _item} <- instruction.goods}
                      value={good}
                      selected={good == instruction.good}
                    >
                      {cargo_name(good)}
                    </option>
                  </select>
                </label>
                <label
                  id={"instruction-quantity-" <> @ship["id"]}
                  phx-hook="TradeQuantity"
                  data-max={instruction.maximum}
                  data-quantity={instruction.quantity}
                >Target lots<input
                  name="quantity"
                  aria-label="Instruction target lots"
                  type="number"
                  min={if instruction.maximum < 1, do: 0, else: 1}
                  max={instruction.maximum}
                  disabled={instruction.maximum < 1}
                  value={instruction.quantity}
                  required
                  class="block w-full rounded bg-slate-800 p-2"
                /></label>
                <label>Limit price ($/lot)<input
                  name="limit"
                  aria-label="Instruction limit price"
                  type="number"
                  min="0"
                  max="10000000000"
                  value={instruction.limit}
                  step="0.01"
                  required
                  class="block w-full rounded bg-slate-800 p-2"
                /></label>
                <label>Purchase cap ($; buys only)<input
                  name="budget"
                  aria-label="Instruction purchase cap"
                  disabled={instruction_value(@instruction_drafts, @ship, "side", "sell") == "sell"}
                  type="number"
                  min="1"
                  max="10000000000"
                  value={instruction.budget}
                  class="block w-full rounded bg-slate-800 p-2 disabled:cursor-not-allowed disabled:opacity-50"
                /></label>
                <input
                  type="hidden"
                  name="onward"
                  value={if length(onwards) == 1, do: hd(onwards), else: ""}
                />
                <p
                  :if={instruction.side == "buy" and length(onwards) != 1}
                  class="col-span-2 text-amber-200"
                >
                  Save an onward destination below before adding buy instructions.
                </p>
                <p :if={duplicate_sell} class="col-span-2 text-amber-200">
                  An active sell instruction already exists for this cargo. Cancel it before adding another.
                </p>
                <button
                  phx-disable-with="Adding…"
                  disabled={
                    duplicate_sell or instruction.maximum < 1 or is_nil(instruction.good) or
                      (instruction.side == "buy" and length(onwards) != 1)
                  }
                  class="self-end rounded bg-teal-700 p-2 disabled:cursor-not-allowed disabled:opacity-50"
                >Add instruction</button>
              </.form>
              <div
                :for={order <- ship_instructions(@view.private, @ship["id"])}
                id={"instruction-" <> order["id"]}
                class="mt-3 border-t border-slate-700 pt-2 text-sm"
              >
                <p>
                  <strong>{String.capitalize(order["side"])} {cargo_name(order["good"])}</strong>
                  at {order["port"]} · {order["filled"]}/{order["quantity"]} lots · {if order[
                                                                                          "side"
                                                                                        ] ==
                                                                                          "buy",
                                                                                        do: "maximum",
                                                                                        else:
                                                                                          "minimum"} {money(
                    order["limit"]
                  )}/lot
                </p>
                <p :if={order["side"] == "buy"}>
                  {money(order["spent"])} spent / {money(order["budget"])} cap
                </p>
                <p>{String.capitalize(order["status"])} · {order["reason"]}</p>
                <button
                  :if={order["status"] in ["planned", "waiting"]}
                  phx-click="cancel-instruction"
                  phx-value-id={order["id"]}
                  class="mt-1 rounded border border-slate-500 px-2 py-1"
                >Cancel order</button>
              </div>
              <p class="my-2 text-sm text-slate-400">
                Plan an onward destination with or without cargo orders. Departure is manual unless automatic departure is enabled for this visit.
              </p>
              <.form
                :for={
                  {shared_port, shared_onwards} <-
                    Enum.sort(visits)
                }
                for={%{}}
                id={"visit-onward-" <> @ship["id"] <> "-" <> shared_port}
                phx-submit="instruction-onward"
                class="mb-3 space-y-2 text-sm"
              >
                <input type="hidden" name="port" value={shared_port} />
                <input type="hidden" name="request_id" value={@request_id} />
                <label>
                  Onward destination after {shared_port}
                  <select
                    name="onward"
                    aria-label="Shared onward port"
                    class="block w-full rounded bg-slate-800 p-2"
                  >
                    <option :if={shared_onwards == []} value="">
                      Choose onward destination
                    </option>
                    <option :if={length(shared_onwards) > 1} value="">
                      Resolve conflicting destinations
                    </option>
                    <option
                      :for={
                        port <-
                          Enum.sort(Map.keys(@definitions.catalogue["ports"])) --
                            [shared_port]
                      }
                      value={port}
                      selected={shared_onwards == [port]}
                    >
                      {port}
                    </option>
                  </select>
                </label>
                <input type="hidden" name="auto_depart" value="false" />
                <label class="flex items-center gap-2">
                  <input
                    type="checkbox"
                    name="auto_depart"
                    value="true"
                    checked={
                      get_in(@view.private, [
                        "visit_plans",
                        @ship["id"] <> "|" <> shared_port,
                        "auto_depart"
                      ]) == true
                    }
                  /> Depart automatically after orders and handling finish
                </label>
                <p class="text-xs text-slate-400">
                  Waits for every order to be filled or cancelled and for sufficient sailing funds. Save to apply.
                </p>
                <p
                  :if={
                    get_in(@view.private, [
                      "visit_plans",
                      @ship["id"] <> "|" <> shared_port,
                      "departure_wait"
                    ])
                  }
                  class="text-amber-300"
                >
                  {get_in(@view.private, [
                    "visit_plans",
                    @ship["id"] <> "|" <> shared_port,
                    "departure_wait"
                  ])}
                </p>
                <p :if={length(shared_onwards) > 1} class="text-amber-300">
                  Existing buy instructions disagree. Purchases are paused until you choose one onward port.
                </p>
                <button
                  phx-disable-with="Updating…"
                  class="rounded border border-slate-500 px-2 py-1"
                >Save onward destination</button>
              </.form>
            </details>
          </div>
        </section>
      </div>
    </section>
    """
  end
end
