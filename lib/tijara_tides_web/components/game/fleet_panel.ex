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
    <section id="ships-panel" class="workspace-panel" aria-label={gettext("Ships")}>
      <h2 class="panel-title">{gettext("Ships")}</h2>
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
      <div class="panel-content" tabindex="0" aria-label={gettext("Fleet and ship details")}>
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
                aria-label={gettext("Dismiss ship information")}
                class="shrink-0 rounded px-2 py-1 text-slate-400 hover:bg-slate-800 hover:text-white"
              >✕</button>
            </div>
            <div class="mt-3 flex flex-wrap items-center gap-2 text-xs">
              <span class="rounded-full border border-slate-600 px-2 py-1 text-slate-300">{l10n(
                @definitions.classes[inspected["class"]]["name"]
              )}</span>
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
              {gettext("Company in bankruptcy — assets in receivership")}
            </p>
            <div class="mt-3 border-t border-slate-700 pt-3">
              <p class="mb-1 text-xs text-slate-400">
                {if inspected["destination"], do: gettext("Route"), else: gettext("Port")}
              </p>
              <p class="flex flex-wrap items-center gap-2 text-sm font-medium">
                <span>{l10n(inspected["port"])}</span>
                <span :if={inspected["destination"]} aria-label={gettext("to")} class="text-teal-400">{sailing_arrow()}</span>
                <span :if={inspected["destination"]}>{l10n(inspected["destination"])}</span>
              </p>
            </div>
          </div>
        </section>
        <section :if={@view.private && @view.private["company"]} class="my-6">
          <h2 class="mb-3 text-xl font-semibold">{gettext("Your fleet")}</h2>
          <details
            id="shipyard"
            phx-mounted={JS.ignore_attributes("open")}
            open={map_size(@view.private["ships"]) == 0}
            class="mb-3 rounded border border-slate-600 p-3"
          >
            <summary class="cursor-pointer">
              {gettext("Buy a ship at %{value1}", value1: l10n(@selected_port))}
            </summary>
            <p class="my-2 text-sm">
              {gettext(
                "Choose a port in the Ports panel to buy there. Ships arrive immediately, empty and docked. Keep cash for cargo, fuel and crew."
              )}
            </p>
            <button
              type="button"
              phx-click={
                JS.set_attribute({"open", ""}, to: "#company-menu")
                |> JS.push("report-close")
              }
              class="mb-2 rounded border border-teal-600 px-3 py-1"
            >{gettext("Arrange a loan")}</button>
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
              <span>{l10n(spec["name"])} · {money(spec["price"])}<br /><small>
                {gettext("%{value1} tonnes · %{value2} m³ capacity",
                  value1: display_number(div(spec["weight"], 1000)),
                  value2: display_number(div(spec["volume"], 1000))
                )}
              </small></span>
              <button
                disabled={
                  spec["price"] >
                    @view.private["company"]["cash"] - @view.private["company"]["reserved"]
                }
                phx-disable-with={gettext("Buying…")}
                class="rounded bg-teal-700 px-3 py-1 disabled:opacity-40"
              >{gettext("Buy ship")}</button>
            </.form>
          </details>

          <form id="fleet-filter" phx-change="fleet-status" class="mb-3 text-sm">
            <label for="fleet-status">{gettext("Ship status")}</label>
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
                {l10n(label)}
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
            {gettext("No ships with this status.")}
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
                {l10n(@definitions.classes[s["class"]]["name"])} · {l10n(s["status"])}
              </p><p>
                {l10n(s["port"])}<span :if={s["destination"]}>{sailing_arrow()} {l10n(
                  s["destination"]
                )}</span>
              </p>
              <p :if={s["arrive_ms"]} class="text-teal-300">
                {gettext("%{value1} min remaining",
                  value1: minutes(max(0, s["arrive_ms"] - @view.public["clock_ms"]))
                )}
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
              {gettext("Book value: %{value1}", value1: finance_money(ship_value.book))}
              <span class="ml-2 text-xs text-slate-400">{gettext(
                "Depreciates over 28 active-world days to 20% of build value."
              )}</span>
            </p>
            <details
              :if={@ship["status"] != "sailing"}
              id={"shipyard-offer-" <> @ship["id"]}
              phx-mounted={JS.ignore_attributes("open")}
              class="my-2"
            >
              <summary class="cursor-pointer">{gettext("Shipyard offer")}</summary>
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
                  phx-disable-with={gettext("Selling…")}
                  data-confirm={
                    gettext("Sell this ship to the shipyard? The ship will leave your fleet.")
                  }
                >{gettext("Sell ship for %{value1}", value1: finance_money(ship_value.proceeds))}</button>
                <span class="text-xs text-slate-400">{gettext("90% of book value.")}</span>
              </.form>
            </details>
            <h3 class="mt-4 mb-2 text-lg font-semibold">
              {gettext("%{value1} — Manifest", value1: @ship["name"])}
            </h3>
            <% occupied =
              Enum.reduce(@ship["cargo"], %{weight: 0, volume: 0}, fn batch, used ->
                good = @definitions.catalogue["goods"][batch["good"]]

                %{
                  weight: used.weight + batch["quantity"] * good["weight_kg"],
                  volume: used.volume + batch["quantity"] * good["volume_l"]
                }
              end) %>
            <p id="ship-capacity" class="text-sm text-slate-400 tabular-nums">
              {gettext("Capacity used: %{value1} / %{value2} kg · %{value3} / %{value4}",
                value1: display_number(occupied.weight),
                value2: display_number(@definitions.classes[@ship["class"]]["weight"]),
                value3: cubic_meters(occupied.volume),
                value4: cubic_meters(@definitions.classes[@ship["class"]]["volume"])
              )}
            </p>
            <p :if={@ship["cargo"] == []} class="mt-2 text-slate-400">{gettext("Empty hold")}</p>
            <div :if={@ship["cargo"] != []} class="mt-3 overflow-x-auto">
              <table class="w-full text-sm" aria-label={gettext("Ship cargo manifest")}>
                <thead class="border-b border-slate-700 text-slate-400">
                  <tr>
                    <th
                      :for={
                        {column, label} <- [
                          {"good", gettext("Cargo")},
                          {"quantity", gettext("Lots")},
                          {"weight", gettext("Weight")},
                          {"volume", gettext("Volume")},
                          {"average_cost", gettext("Avg. cost")},
                          {"expires_ms", gettext("First expiry")}
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
                        {l10n(label)}<span aria-hidden="true" class="ml-1">{if elem(
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
                        aria-label={
                          gettext("View markets for %{cargo}", cargo: cargo_name(b["good"]))
                        }
                        class="rounded text-left text-teal-300 underline decoration-teal-700 underline-offset-2 hover:text-teal-100 focus-visible:outline-2 focus-visible:outline-teal-300"
                      >{cargo_name(b["good"])}</button>
                    </th>
                    <td class="px-4 py-3 text-right tabular-nums">{display_number(b["quantity"])}</td>
                    <td class="whitespace-nowrap px-4 py-3 text-right tabular-nums">
                      {gettext("%{value1} kg",
                        value1:
                          display_number(
                            b["quantity"] * @definitions.catalogue["goods"][b["good"]]["weight_kg"]
                          )
                      )}
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
                        {gettext("%{value1} min",
                          value1: div(max(0, b["expires_ms"] - @view.public["clock_ms"]), 60_000)
                        )}
                      <% else %>
                        <span aria-label={gettext("Does not expire")}>—</span>
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
                aria-label={gettext("Destination")}
                class="rounded bg-slate-800 px-3 py-2"
              ><option value="" selected={is_nil(@destination) or @destination == ""}>
                {gettext("Choose a destination before buying")}
              </option><option
                :for={
                  name <-
                    Enum.sort(Map.keys(@definitions.catalogue["ports"])) -- [@ship["port"]]
                }
                value={name}
                selected={name == @destination}
              >
                {l10n(name)}
              </option></select>
            </.form>
            <div :if={@preview} class="mt-3 flex flex-wrap items-center gap-3">
              <span>
                {gettext(
                  "%{value1} min · fuel %{value2} · estimated crew %{value3} · canals %{value4}",
                  value1: minutes(@preview["duration_ms"]),
                  value2: money(@preview["fuel"]),
                  value3: money(@preview["crew_estimate"]),
                  value4: money(@preview["canal_fees"])
                )}
              </span><button
                phx-click="sail"
                phx-value-request_id={@request_id}
                class="rounded bg-teal-600 px-4 py-2"
              >{gettext("Reserve fuel and sail")}</button>
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
                {gettext("Next port cargo instructions")}
              </summary>
              <p class="my-2 text-sm text-slate-400">
                {gettext(
                  "Execute when berthed. Sales unload before purchases load. Partial fills retry while waiting; sailing cancels any remainder. Prices are per lot, excluding handling. A purchase cap includes all purchase costs and does not reserve cash."
                )}
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
                {gettext("Choose a destination in the voyage controls before adding instructions.")}
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
                <p class="col-span-2 font-semibold">
                  {gettext("Instructions at %{value1}", value1: l10n(visit_port))}
                </p>
                <label>
                  {gettext("Action")}
                  <select
                    name="side"
                    aria-label={gettext("Instruction action")}
                    class="block w-full rounded bg-slate-800 p-2"
                  ><option
                    value="sell"
                    selected={
                      instruction_value(@instruction_drafts, @ship, "side", "sell") ==
                        "sell"
                    }
                  >
                    {gettext("Sell")}
                  </option><option
                    value="buy"
                    selected={instruction_value(@instruction_drafts, @ship, "side", "sell") == "buy"}
                  >
                    {gettext("Buy")}
                  </option></select>
                </label>
                <label>
                  {gettext("Cargo")}
                  <select
                    name="good"
                    aria-label={gettext("Instruction cargo")}
                    disabled={instruction.goods == []}
                    class="block w-full rounded bg-slate-800 p-2"
                  >
                    <option :if={instruction.goods == []} value="">
                      {gettext("No cargo available")}
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
                >{gettext("Target lots")}<input
                  name="quantity"
                  aria-label={gettext("Instruction target lots")}
                  type="number"
                  min={if instruction.maximum < 1, do: 0, else: 1}
                  max={instruction.maximum}
                  disabled={instruction.maximum < 1}
                  value={instruction.quantity}
                  required
                  class="block w-full rounded bg-slate-800 p-2"
                /></label>
                <label>{gettext("Limit price ($/lot)")}<input
                  name="limit"
                  aria-label={gettext("Instruction limit price")}
                  type="number"
                  min="0"
                  max="10000000000"
                  value={instruction.limit}
                  step="0.01"
                  required
                  class="block w-full rounded bg-slate-800 p-2"
                /></label>
                <label>{gettext("Purchase cap ($; buys only)")}<input
                  name="budget"
                  aria-label={gettext("Instruction purchase cap")}
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
                  {gettext("Save an onward destination below before adding buy instructions.")}
                </p>
                <p :if={duplicate_sell} class="col-span-2 text-amber-200">
                  {gettext(
                    "An active sell instruction already exists for this cargo. Cancel it before adding another."
                  )}
                </p>
                <button
                  phx-disable-with={gettext("Adding…")}
                  disabled={
                    duplicate_sell or instruction.maximum < 1 or is_nil(instruction.good) or
                      (instruction.side == "buy" and length(onwards) != 1)
                  }
                  class="self-end rounded bg-teal-700 p-2 disabled:cursor-not-allowed disabled:opacity-50"
                >{gettext("Add instruction")}</button>
              </.form>
              <div
                :for={order <- ship_instructions(@view.private, @ship["id"])}
                id={"instruction-" <> order["id"]}
                class="mt-3 border-t border-slate-700 pt-2 text-sm"
              >
                <p>
                  <strong>{l10n(String.capitalize(order["side"]))} {cargo_name(order["good"])}</strong>
                  {gettext("at %{value1} · %{value2}/%{value3} lots · %{value4} %{value5}/lot",
                    value1: l10n(order["port"]),
                    value2: display_number(order["filled"]),
                    value3: display_number(order["quantity"]),
                    value4:
                      if(
                        order[
                          "side"
                        ] ==
                          "buy",
                        do: gettext("maximum"),
                        else: gettext("minimum")
                      ),
                    value5: money(order["limit"])
                  )}
                </p>
                <p :if={order["side"] == "buy"}>
                  {gettext("%{value1} spent / %{value2} cap",
                    value1: money(order["spent"]),
                    value2: money(order["budget"])
                  )}
                </p>
                <p>{l10n(order["status"])} · {l10n(order["reason"] || "")}</p>
                <button
                  :if={order["status"] in ["planned", "waiting"]}
                  phx-click="cancel-instruction"
                  phx-value-id={order["id"]}
                  class="mt-1 rounded border border-slate-500 px-2 py-1"
                >{gettext("Cancel order")}</button>
              </div>
              <p class="my-2 text-sm text-slate-400">
                {gettext(
                  "Plan an onward destination with or without cargo orders. Departure is manual unless automatic departure is enabled for this visit."
                )}
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
                  {gettext("Onward destination after %{value1}", value1: l10n(shared_port))}
                  <select
                    name="onward"
                    aria-label={gettext("Shared onward port")}
                    class="block w-full rounded bg-slate-800 p-2"
                  >
                    <option :if={shared_onwards == []} value="">
                      {gettext("Choose onward destination")}
                    </option>
                    <option :if={length(shared_onwards) > 1} value="">
                      {gettext("Resolve conflicting destinations")}
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
                      {l10n(port)}
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
                  />
                  {gettext("Depart automatically after orders and handling finish")}
                </label>
                <p class="text-xs text-slate-400">
                  {gettext(
                    "Waits for every order to be filled or cancelled and for sufficient sailing funds. Save to apply."
                  )}
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
                  {l10n(
                    get_in(@view.private, [
                      "visit_plans",
                      @ship["id"] <> "|" <> shared_port,
                      "departure_wait"
                    ])
                  )}
                </p>
                <p :if={length(shared_onwards) > 1} class="text-amber-300">
                  {gettext(
                    "Existing buy instructions disagree. Purchases are paused until you choose one onward port."
                  )}
                </p>
                <button
                  phx-disable-with={gettext("Updating…")}
                  class="rounded border border-slate-500 px-2 py-1"
                >{gettext("Save onward destination")}</button>
              </.form>
            </details>
          </div>
        </section>
      </div>
    </section>
    """
  end
end
