defmodule TijaraTidesWeb.GameUI.FleetPanel do
  @moduledoc "FleetPanel rendering; events remain owned by GameLive."
  use TijaraTidesWeb, :html
  import TijaraTidesWeb.GameUI.Presentation
  alias TijaraTides.UseCases.GameQueries

  attr :definitions, :any, required: true
  attr :destination_picker_open, :boolean, default: false
  attr :destination, :any, required: true
  attr :fleet_status, :any, required: true
  attr :inspected_ship, :any, required: true
  attr :instruction_drafts, :any, required: true
  attr :manifest_sort, :any, required: true
  attr :preview, :any, required: true
  attr :public_fleet_grouping, :string, default: "location"
  attr :request_id, :any, required: true
  attr :route_drafts, :any, required: true
  attr :selected_port, :any, required: true
  attr :selected_ship, :any, required: true
  attr :ship, :any, required: true
  attr :view, :any, required: true

  def panel(assigns) do
    ~H"""
    <section id="ships-panel" class="workspace-panel" aria-label={gettext("Ships")}>
      <h2 class="panel-title"><.emoji symbol="🚢" />{gettext("Ships")}</h2>
      <div class="panel-content" tabindex="0" aria-label={gettext("Fleet and ship details")}>
        <%!-- Without a company, the All ships card is the inspected ship's summary. --%>
        <section
          :if={
            @inspected_ship && @view.public["ships"][@inspected_ship] && @view.private &&
              @view.private["company"] && !@view.private["ships"][@inspected_ship]
          }
          id="public-ship-inspector"
          class="my-6 rounded-xl border border-slate-700 p-5"
        >
          <% inspected = @view.public["ships"][@inspected_ship] %>
          <.weather_notice ship={inspected} clock={@view.public["clock_ms"]} />
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
              {if @view.public["companies"][inspected["company_id"]]["closure_reason"] == "dormant",
                do: gettext("Company closed for dormancy — assets in receivership"),
                else: gettext("Company in bankruptcy — assets in receivership")}
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
        <section
          :if={!(@view.private && @view.private["company"])}
          id="public-fleet"
          class="my-6"
        >
          <% groups =
            GameQueries.public_fleet_groups(@definitions, @view.public, @public_fleet_grouping) %>
          <div class="mb-3 flex flex-wrap items-center justify-between gap-3">
            <h2 class="text-xl font-semibold">
              <.emoji symbol="🚢" />{gettext("All ships")} · {ship_count(
                map_size(@view.public["ships"])
              )}
            </h2>
            <form id="public-fleet-grouping" phx-change="public-fleet-grouping">
              <label class="text-sm text-slate-300">
                {gettext("Group by")}
                <select
                  name="grouping"
                  aria-label={gettext("Group all ships")}
                  class="ml-2 rounded bg-slate-800 px-3 py-2"
                >
                  <option
                    :for={
                      {value, label} <- [
                        {"location", gettext("Location")},
                        {"company", gettext("Company")},
                        {"class", gettext("Class")}
                      ]
                    }
                    value={value}
                    selected={@public_fleet_grouping == value}
                  >
                    {label}
                  </option>
                </select>
              </label>
            </form>
          </div>
          <p :if={groups == []} class="text-sm text-slate-400">
            {gettext("No ships at sea or in port yet.")}
          </p>
          <details
            :for={group <- groups}
            id={public_fleet_group_id(group.key)}
            open
            phx-mounted={JS.ignore_attributes("open")}
            class="mt-3 rounded border border-slate-700 px-3 py-2"
          >
            <summary class="cursor-pointer">
              {public_fleet_label(group.key, @definitions, @view.public)} · {ship_count(
                length(group.ships)
              )}
            </summary>
            <div class="fleet-list mt-2">
              <TijaraTidesWeb.GameUI.ShipCard.card
                :for={ship <- group.ships}
                ship={ship}
                definitions={@definitions}
                clock={@view.public["clock_ms"]}
                queue_position={ship["queue_position"]}
                company={
                  if @public_fleet_grouping != "company",
                    do: company_name(@view.public, ship["company_id"])
                }
                pressed={ship["id"] == @inspected_ship}
                id={"public-ship-" <> ship["id"]}
                data-public-ship={ship["id"]}
                phx-click="inspect-ship"
                phx-value-id={ship["id"]}
              />
            </div>
          </details>
        </section>
        <section :if={@view.private && @view.private["company"]} class="my-6">
          <h2 class="mb-3 text-xl font-semibold"><.emoji symbol="🚢" />{gettext("Your fleet")}</h2>
          <details
            id="shipyard"
            phx-mounted={JS.ignore_attributes("open")}
            open={map_size(@view.private["ships"]) == 0}
            class="mb-3 rounded border border-slate-600 p-3"
          >
            <summary class="cursor-pointer">
              <.emoji symbol="🚢" />{gettext("Buy a ship at %{value1}",
                value1: l10n(@selected_port)
              )}
            </summary>
            <p class="my-2 text-sm">
              {gettext(
                "Choose a port in the Ports panel to buy there. Ships arrive immediately, empty and docked. Keep cash for cargo, fuel and crew."
              )}
            </p>
            <.form
              for={%{}}
              id="shipyard-purchase"
              phx-submit="purchase-ship"
              phx-hook="ExchangeDraft"
              class="my-2"
            >
              <input type="hidden" name="request_id" value={@request_id} />
              <div class="mb-2 flex flex-wrap items-center gap-3">
                <button
                  type="button"
                  phx-click={
                    JS.set_attribute({"open", ""}, to: "#company-menu")
                    |> JS.push("report-close")
                  }
                  class="rounded border border-teal-600 px-3 py-1"
                >{gettext("Arrange a loan")}</button>
                <label class="flex max-w-full flex-wrap items-center gap-2 text-sm">
                  {gettext("Ship name (optional):")}
                  <input
                    type="text"
                    name="name"
                    maxlength="80"
                    placeholder={gettext("Leave blank for an automatic name")}
                    class="block w-[34ch] max-w-full shrink-0 rounded bg-slate-800 px-2 py-1"
                  />
                </label>
              </div>
              <div
                :for={{class, spec} <- Enum.sort(@definitions.classes)}
                class="my-2 flex flex-wrap items-center justify-between gap-2"
              >
                <input type="hidden" name={"price_limits[" <> class <> "]"} value={spec["price"]} />
                <span>{l10n(spec["name"])} · {money(spec["price"])}<br /><small>
                  {gettext("%{value1} tonnes · %{value2} m³ capacity",
                    value1: display_number(div(spec["weight"], 1000)),
                    value2: display_number(div(spec["volume"], 1000))
                  )}
                </small></span>
                <button
                  type="submit"
                  name="class"
                  value={class}
                  disabled={
                    spec["price"] >
                      @view.private["company"]["cash"] - @view.private["company"]["reserved"]
                  }
                  phx-disable-with={gettext("Buying…")}
                  class="rounded bg-teal-700 px-3 py-1 disabled:opacity-40"
                ><.emoji symbol="🚢" />{gettext("Buy ship")}</button>
              </div>
            </.form>
          </details>

          <.form
            for={%{}}
            id="departure-funding-policy"
            phx-hook="ExchangeDraft"
            phx-submit="funding-policy"
            class="mb-3 flex flex-wrap items-end gap-2 text-sm"
          >
            <input type="hidden" name="request_id" value={@request_id} />
            <label>
              {gettext("Automatic departure funding policy")}
              <select name="policy" class="block rounded bg-slate-800 p-2">
                <option
                  value="wait"
                  selected={(@view.private["account"]["funding_policy"] || "wait") == "wait"}
                >
                  {gettext("Wait and notify")}
                </option>
                <option
                  value="reduced"
                  selected={@view.private["account"]["funding_policy"] == "reduced"}
                >
                  {gettext("Sail with a reduced budget")}
                </option>
                <option value="skip" selected={@view.private["account"]["funding_policy"] == "skip"}>
                  {gettext("Skip purchases")}
                </option>
              </select>
            </label>
            <button class="rounded border px-3 py-2">{gettext("Save policy")}</button>
          </.form>
          <details
            id="departure-funding-help"
            phx-mounted={JS.ignore_attributes("open")}
            class="mb-3 text-sm text-slate-400"
          >
            <summary class="cursor-pointer">{gettext("How these policies work")}</summary>
            <p class="my-2">
              {gettext(
                "Choose what happens when fuel and canal fees can be funded, but the full configured purchase budget cannot."
              )}
            </p>
            <dl class="space-y-2">
              <div>
                <dt class="font-semibold">{gettext("Wait and notify")}</dt>
                <dd>
                  {gettext(
                    "Keep the ship in port until fuel, canal fees and the full purchase budget are available. This preserves the planned buying capacity, but delays deliveries. The ship retries automatically; you are notified when it is blocked and when it departs."
                  )}
                </dd>
              </div>
              <div>
                <dt class="font-semibold">{gettext("Sail with a reduced budget")}</dt>
                <dd>
                  {gettext(
                    "Fund fuel and canal fees, then reserve the remaining cash for purchases, up to the configured budget. The ship keeps moving, but may buy less or nothing. Its purchase budget is not automatically topped up at arrival."
                  )}
                </dd>
              </div>
              <div>
                <dt class="font-semibold">{gettext("Skip purchases")}</dt>
                <dd>
                  {gettext(
                    "Fund fuel and canal fees and sail without new purchases for that visit. This preserves cash and avoids waiting for a purchase budget, but leaves buying targets unfilled. Unfilled remote buy orders linked to the visit are cancelled; completed fills remain available for collection."
                  )}
                </dd>
              </div>
            </dl>
            <p class="my-2">
              {gettext(
                "This policy applies to all automatic departures. Fuel is always fully funded. Reduced budgets stay strict at arrival; skipped visits can still deliver and collect owned cargo."
              )}
            </p>
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
            <TijaraTidesWeb.GameUI.ShipCard.card
              :for={{id, s} <- Enum.sort(@view.private["ships"])}
              :if={@fleet_status == "all" || s["status"] == @fleet_status}
              ship={s}
              definitions={@definitions}
              clock={@view.public["clock_ms"]}
              queue_position={@view.public["ships"][id]["queue_position"]}
              pressed={id == @selected_ship}
              phx-click="ship"
              phx-value-id={id}
            />
          </div>
          <div :if={@ship} class="mt-2 rounded-xl bg-slate-900 px-5 pt-2 pb-5">
            <% berth = TijaraTides.UseCases.GameQueries.berth_view(@ship, @definitions) %>
            <TijaraTidesWeb.GameUI.ShipBerth.scene
              :if={@ship["status"] in ["docked", "loading", "unloading"]}
              ship={@ship}
              clock={@view.public["clock_ms"]}
              queue_position={get_in(@view.public, ["ships", @ship["id"], "queue_position"])}
              liquid={@definitions.classes[@ship["class"]]["hold"] == "liquid"}
              cargo_volume_l={berth.cargo_volume_l}
              capacity_l={berth.capacity_l}
            />
            <p :if={@view.public["ships"][@ship["id"]]["queue_position"]} class="mb-3 text-amber-300">
              {gettext("Queue position: %{position}",
                position: display_number(@view.public["ships"][@ship["id"]]["queue_position"])
              )}
            </p>
            <TijaraTidesWeb.GameUI.QueuedTrade.notice
              :if={@ship["pending_side"]}
              id="fleet-queued-trade"
              ship={@ship}
              public={@view.public}
              reason={get_in(@view.private, ["queued_trade_status", @ship["id"]])}
            />
            <% ship_value =
              GameQueries.ship_sale_value(
                @ship,
                @view.public["clock_ms"]
              ) %>
            <details
              id={"shipyard-offer-" <> @ship["id"]}
              phx-mounted={JS.ignore_attributes("open")}
              class="mb-2"
            >
              <summary class="cursor-pointer">
                <.emoji symbol="🔎" />{gettext("Ship details")}
              </summary>
              <.form
                for={%{}}
                id={"rename-ship-" <> @ship["id"] <> "-" <> Base.url_encode64(@ship["name"], padding: false)}
                phx-submit="rename-ship"
                phx-hook="ExchangeDraft"
                class="my-3 flex flex-wrap items-end gap-2"
              >
                <input type="hidden" name="request_id" value={@request_id} />
                <input type="hidden" name="ship" value={@ship["id"]} />
                <label class="flex items-center gap-2 text-sm">
                  {gettext("Ship name:")}
                  <input
                    type="text"
                    name="name"
                    value={@ship["name"]}
                    required
                    maxlength="80"
                    class="block rounded bg-slate-800 px-2 py-1"
                  />
                </label>
                <button
                  phx-disable-with={gettext("Renaming…")}
                  class="rounded bg-teal-700 px-3 py-1"
                >{gettext("Rename ship")}</button>
              </.form>

              <p class="text-sm">
                {gettext("Book value: %{value1}", value1: finance_money(ship_value.book))}
                <span class="ml-2 text-xs text-slate-400">{gettext(
                  "Depreciates over %{days} active-world days to %{residual}% of build value.",
                  days: display_number(GameQueries.maintenance_curve().life_days),
                  residual: display_number(GameQueries.maintenance_curve().residual_percent)
                )}</span>
              </p>
              <% maintenance = GameQueries.ship_maintenance(@ship, @view.public["clock_ms"]) %>
              <p class="text-sm">
                {gettext(
                  "Maintenance: next day %{day}; next 7 days %{week}. New hull: %{replacement} per day.",
                  day: money(maintenance.next_day),
                  week: money(maintenance.next_week),
                  replacement: money(maintenance.replacement_day)
                )}
              </p>
              <p class="text-xs text-slate-400">
                {gettext(
                  "Maintenance is flat for %{days} active-world days, then rises linearly. At age %{crossover} days its rate equals a new hull's maintenance plus depreciation. Crew costs are separate.",
                  days: display_number(GameQueries.maintenance_curve().life_days),
                  crossover: display_number(GameQueries.maintenance_curve().crossover_days)
                )}
              </p>
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
              <.emoji symbol="📋" />{gettext("%{value1} — Manifest", value1: @ship["name"])}
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
                      ><.cargo_label good={b["good"]} /></button>
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
            <form
              :if={@ship["status"] == "sailing"}
              id="reroute-selector"
              phx-change="preview"
              class="mt-3"
            >
              <label class="text-sm">
                <.emoji symbol="🧭" />{gettext("Reroute ship")}
                <select name="destination" class="block rounded bg-slate-800 p-2">
                  <option value="">{gettext("Choose a new destination")}</option>
                  <option
                    :for={port <- Enum.sort(Map.keys(@definitions.catalogue["ports"]))}
                    :if={port != @ship["destination"]}
                    value={port}
                    selected={port == @destination}
                  >
                    {l10n(port)}
                  </option>
                </select>
              </label>
            </form>
            <button
              :if={@ship["status"] in ["docked", "loading", "unloading"]}
              id="destination-picker-trigger"
              type="button"
              phx-click={
                JS.remove_attribute("open", to: "#company-menu") |> JS.push("destination-picker-open")
              }
              aria-haspopup="dialog"
              aria-expanded={to_string(@destination_picker_open)}
              class="mt-4 rounded border border-teal-700 px-3 py-2 text-teal-200"
            >
              <.emoji symbol="🧭" />{if @destination,
                do: gettext("Destination: %{port}", port: l10n(@destination)),
                else: gettext("Choose destination")}
            </button>
            <TijaraTidesWeb.GameUI.DestinationPicker.panel
              :if={@destination_picker_open && @ship["status"] in ["docked", "loading", "unloading"]}
              definitions={@definitions}
              view={@view}
              ship={@ship}
              destination={@destination}
            />
            <TijaraTidesWeb.GameUI.QueuedDeparture.panel
              ship={@ship}
              private={@view.private}
              destination={@destination}
              request_id={@request_id}
            />
            <p :if={@preview && @ship["status"] == "sailing"} class="mt-2 text-sm text-teal-200">
              {gettext(
                "Additional fuel: %{extra} · released fuel: %{released}. Dashed teal shows the revised course. Port instructions stay at their original ports; repeating routes pause.",
                extra: money(@preview["additional_fuel"]),
                released: money(@preview["released_fuel"])
              )}
            </p>
            <div :if={@preview} id="voyage-preview" class="mt-3 flex flex-wrap items-center gap-3">
              <span>
                {gettext(
                  "%{value1} min · fuel %{value2} · estimated crew %{value3} · canals %{value4}",
                  value1: minutes(@preview["duration_ms"]),
                  value2: money(@preview["fuel"]),
                  value3: money(@preview["crew_estimate"]),
                  value4: money(@preview["canal_fees"])
                )}
                {gettext(" · estimated maintenance %{cost}",
                  cost: money(@preview["maintenance_estimate"])
                )}
              </span><button
                id="sail-preview"
                phx-click="sail"
                phx-value-request_id={@request_id}
                class="rounded bg-teal-600 px-4 py-2"
              ><.emoji symbol="⛵" />{if @ship["status"] == "sailing",
                do: gettext("Confirm reroute"),
                else: gettext("Reserve fuel and sail")}</button>
              <p :if={(@preview["weather_delay_ms"] || 0) > 0} class="text-xs text-amber-300">
                {gettext("Known weather delay: %{minutes} min; included in this estimate.",
                  minutes: minutes(@preview["weather_delay_ms"])
                )}
              </p>
              <.voyage_freshness
                id={"preview-freshness-" <> @ship["id"]}
                estimates={@preview["freshness"]}
              />
            </div>
            <p :if={@preview} class="text-xs text-slate-400">
              {gettext(
                "Departure reserves fuel and canal fees only. Crew and maintenance accrue as the voyage runs and become unpaid bills if available cash falls short."
              )}
            </p>
            <.voyage_freshness
              id={"voyage-freshness-" <> @ship["id"]}
              estimates={@view.private["voyage_freshness"][@ship["id"]]}
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
                <.emoji symbol="📋" />{gettext("Next port cargo instructions")}
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
                  @view.private["company"],
                  @view
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
                      {cargo_option(good)}
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
                <label>{gettext("Minimum shelf life (minutes; buys only)")}<input
                  name="freshness_minutes"
                  aria-label={gettext("Minimum remaining shelf life")}
                  type="number"
                  min="0"
                  max="43200"
                  step="1"
                  disabled={instruction.side == "sell"}
                  value={instruction_value(@instruction_drafts, @ship, "freshness_minutes", "")}
                  class="block w-full rounded bg-slate-800 p-2 disabled:opacity-40"
                /></label>
                <p class="self-center text-xs text-slate-400">
                  {gettext(
                    "Checked at purchase or collection, in active-world time. Blank accepts any unspoiled cargo."
                  )}
                </p>
                <label :if={instruction.side == "sell"}>
                  {gettext("Markdown preset (optional)")}
                  <select name="preset" class="block w-full rounded bg-slate-800 p-2">
                    <option value="">{gettext("Off")}</option>
                    <option
                      :for={
                        preset <-
                          Enum.sort_by(
                            Map.values(@view.private["markdown_presets"] || %{}),
                            & &1["name"]
                          )
                      }
                      value={preset["id"]}
                      selected={
                        instruction_value(@instruction_drafts, @ship, "preset", "") == preset["id"]
                      }
                    >
                      {preset["name"]}
                    </option>
                  </select>
                </label>
                <label>{gettext("Expires after (active minutes; optional)")}<input
                  name="expiry_minutes"
                  aria-label={gettext("Instruction expiry minutes")}
                  type="number"
                  min="1"
                  max="43200"
                  step="1"
                  value={instruction_value(@instruction_drafts, @ship, "expiry_minutes", "")}
                  class="block w-full rounded bg-slate-800 p-2"
                /></label>
                <p class="self-center text-xs text-slate-400">
                  {gettext(
                    "Blank means no expiry. Starts when added; pauses while the world is offline."
                  )}
                </p>
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
                  <strong>{l10n(String.capitalize(order["side"]))}
                  <.cargo_label good={order["good"]} /></strong>
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
                <p :if={order["min_remaining_ms"] && order["min_remaining_ms"] > 0}>
                  {gettext("Minimum remaining shelf life: %{minutes} min",
                    minutes: display_number(div(order["min_remaining_ms"], 60_000))
                  )}
                </p>
                <p :if={order["expires_ms"] && order["status"] in ["planned", "waiting"]}>
                  {gettext("Expiry remaining: %{time} of active-world time (hours:minutes:seconds).",
                    time: active_countdown(order["expires_ms"] - @view.public["clock_ms"])
                  )}
                </p>
                <button
                  :if={order["status"] in ["planned", "waiting"]}
                  id={"fleet-cancel-instruction-" <> order["id"]}
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
                    required
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
                <TijaraTidesWeb.GameUI.DepartureWait.notice
                  ship={@ship}
                  plan={@view.private["visit_plans"][@ship["id"] <> "|" <> shared_port]}
                  orders={Map.values(@view.private["ship_instructions"] || %{})}
                />
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
            <div
              :for={{_, plan} <- @view.private["visit_plans"] || %{}}
              :if={plan["ship_id"] == @ship["id"] && !@view.private["ship_routes"][@ship["id"]]}
              class="mt-3 text-sm"
            >
              <.form
                for={%{}}
                id={"visit-budget-" <> plan["id"]}
                phx-hook="ExchangeDraft"
                phx-submit="visit-budget"
                class="flex flex-wrap items-end gap-2"
              >
                <input type="hidden" name="port" value={plan["port"]} />
                <input type="hidden" name="request_id" value={@request_id} />
                <label>
                  {gettext("Advance purchase budget at %{port} ($, optional)",
                    port: l10n(plan["port"])
                  )}
                  <input
                    name="amount"
                    type="number"
                    min="0"
                    max="10000000000"
                    step="0.01"
                    value={if plan["advance_budget"], do: plan["advance_budget"] / 100, else: ""}
                    class="block rounded bg-slate-800 p-2"
                  />
                </label>
                <button class="rounded border px-3 py-2">{gettext("Save budget")}</button>
              </.form>
            </div>
            <TijaraTidesWeb.ShipRouteEditor.panel
              ship={@ship}
              model={
                GameQueries.route_editor(
                  @view.private,
                  @ship,
                  @definitions.catalogue,
                  @view.public["clock_ms"]
                )
              }
              catalogue={@definitions.catalogue}
              drafts={@route_drafts}
              request_id={@request_id}
              clock={@view.public["clock_ms"]}
            />
          </div>
        </section>
      </div>
    </section>
    """
  end

  defp ship_count(count), do: ngettext("%{count} ship", "%{count} ships", count)

  defp company_name(public, id),
    do: get_in(public, ["companies", id, "name"]) || gettext("Unknown company")

  defp public_fleet_label({:port, region}, _definitions, _public), do: l10n(region)

  defp public_fleet_label({:route, first, second}, _definitions, _public),
    do: l10n(first) <> " ↔ " <> l10n(second)

  defp public_fleet_label({:within, region}, _definitions, _public),
    do: gettext("Within %{region}", region: l10n(region))

  defp public_fleet_label({:company, id}, _definitions, public), do: company_name(public, id)

  defp public_fleet_label({:class, id}, definitions, _public),
    do: l10n(get_in(definitions.classes, [id, "name"]) || id || "Unknown class")

  # Keep browser-owned expansion state while ships move between groups.
  defp public_fleet_group_id(key),
    do:
      "public-fleet-group-" <>
        Base.url_encode64(Jason.encode!(Tuple.to_list(key)), padding: false)
end
