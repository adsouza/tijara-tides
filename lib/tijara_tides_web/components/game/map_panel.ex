defmodule TijaraTidesWeb.GameUI.MapPanel do
  @moduledoc "MapPanel rendering; events remain owned by GameLive."
  use TijaraTidesWeb, :html
  import TijaraTidesWeb.GameUI.Presentation
  alias TijaraTidesWeb.WorldMap

  attr :definitions, :any, required: true
  attr :inspected_ship, :any, required: true
  attr :map_filters_open, :any, required: true
  attr :map_region, :any, required: true
  attr :map_ship_classes, :any, required: true
  attr :map_ships, :any, required: true
  attr :map_show_others, :any, required: true
  attr :selected_port, :any, required: true
  attr :view, :any, required: true

  def panel(assigns) do
    ~H"""
    <section
      id="map-panel"
      data-regional={to_string(not is_nil(@map_region))}
      class="overflow-hidden rounded-xl border border-slate-700 bg-slate-950"
    >
      <% viewport = WorldMap.viewport(@definitions.catalogue, @map_region) %>
      <div class="map-toolbar px-3 py-2">
        <button
          id="map-expand"
          type="button"
          data-map-expand
          aria-expanded="false"
          aria-controls="map-panel"
          class="map-expand rounded border border-slate-600 px-3 py-1 text-xs"
        >
          <span class="map-expand-label">Expand <span class="map-button-word">map ⛶</span></span>
          <span class="map-restore-label">Restore main screen ↙</span>
        </button>
        <button
          id="map-filter-toggle"
          phx-click="toggle-map-filters"
          aria-expanded={to_string(@map_filters_open)}
          aria-controls="map-filters"
          class="rounded border border-slate-600 px-3 py-1 text-xs"
        >
          Ship <span class="map-button-word">filters {if @map_filters_open, do: "▴", else: "▾"}</span>
        </button>
        <form
          :if={@map_filters_open}
          id="map-filters"
          phx-change="map-filters"
          class="mt-2 rounded border border-slate-600 bg-slate-900 p-3 text-xs"
        >
          <fieldset>
            <legend class="mb-2 text-slate-400">Ship types</legend>
            <input type="hidden" name="classes[]" value="" />
            <div class="grid grid-cols-2 gap-2">
              <label
                :for={
                  {id, ship_class} <-
                    Enum.sort_by(@definitions.classes, fn {_, c} -> c["name"] end)
                }
                class="flex items-center gap-2"
              >
                <input
                  type="checkbox"
                  name="classes[]"
                  value={id}
                  checked={MapSet.member?(@map_ship_classes, id)}
                />
                {ship_class["name"]}
              </label>
            </div>
          </fieldset>
          <label
            :if={@view.private}
            class="mt-3 flex items-center gap-2 border-t border-slate-700 pt-2"
          >
            <input type="hidden" name="show_others" value="false" />
            <input
              type="checkbox"
              name="show_others"
              value="true"
              checked={@map_show_others}
            /> Show other companies’ ships
          </label>
        </form>
      </div>
      <div
        :if={@map_region}
        class="map-region-heading flex items-center justify-between px-4 py-3"
      >
        <h2 class="text-lg">{@map_region}</h2>
        <button phx-click="map-world" class="rounded border border-teal-700 px-3 py-2">World view</button>
      </div>
      <svg
        id="world-map"
        viewBox={viewport.box}
        role="group"
        aria-label="World ports and public ship positions on a Equal Earth map"
        class="w-full"
      >
        <polygon
          :for={ring <- Map.get(@definitions.regional_land, @map_region, @definitions.land)}
          vector-effect="non-scaling-stroke"
          points={WorldMap.points(ring)}
          fill="#172f39"
          stroke="#294551"
          stroke-width="0.4"
        />
        <polyline
          :for={lon <- -180..180//30}
          vector-effect="non-scaling-stroke"
          points={WorldMap.points(for lat <- -90..90//2, do: [lon, lat])}
          fill="none"
          stroke="#1e293b"
        />
        <polyline
          :for={lat <- -60..60//30}
          vector-effect="non-scaling-stroke"
          points={WorldMap.points(for lon <- -180..180//2, do: [lon, lat])}
          fill="none"
          stroke="#1e293b"
        />
        <g :for={{id, s} <- @map_ships} data-map-route={id}>
          <% route =
            @definitions.catalogue["routes"][s["port"] <> "|" <> s["destination"]][
              "coordinates"
            ] %>
          <path
            vector-effect="non-scaling-stroke"
            d={WorldMap.path(route)}
            fill="none"
            stroke="#155e75"
            stroke-width="1"
          />
          <path
            :for={arrow <- WorldMap.route_arrows(route, viewport.scale)}
            d="M -4 -3 L 3 0 L -4 3"
            transform={"translate(#{arrow.x} #{arrow.y}) rotate(#{arrow.angle}) scale(#{viewport.scale})"}
            fill="none"
            stroke="#38b8cf"
            stroke-width="1.5"
            vector-effect="non-scaling-stroke"
            pointer-events="none"
            aria-hidden="true"
          />
        </g>
        <g
          :for={marker <- WorldMap.markers(@definitions.catalogue, @map_region)}
          role="button"
          tabindex="0"
          aria-label={
            if length(marker.ports) > 1,
              do: "#{marker.name}: #{length(marker.ports)} ports",
              else: "Select #{marker.name}"
          }
          phx-click={if length(marker.ports) > 1, do: "map-region", else: "port"}
          phx-keydown={if length(marker.ports) > 1, do: "map-region", else: "port"}
          phx-key="Enter"
          phx-value-id={marker.name}
          class="cursor-pointer"
        >
          <circle
            cx={hd(marker.center)}
            cy={List.last(marker.center)}
            r={16 * viewport.scale}
            fill="transparent"
          />
          <circle
            cx={hd(marker.center)}
            cy={List.last(marker.center)}
            r={
              if(length(marker.ports) > 1,
                do: 11,
                else: if(marker.name == @selected_port, do: 7, else: 5)
              ) * viewport.scale
            }
            class="port-marker-dot"
            fill="#2dd4bf"
            stroke="#0f172a"
            vector-effect="non-scaling-stroke"
          >
            <title>
              {marker.name} — {if length(marker.ports) > 1,
                do: Enum.join(marker.ports, ", "),
                else: @definitions.catalogue["ports"][marker.name]["harbor"]}
            </title>
          </circle>
          <text
            :if={@map_region}
            data-port-label
            data-label-x={hd(marker.center)}
            data-label-y={List.last(marker.center)}
            data-label-dx={WorldMap.label_position(marker.name).dx}
            data-label-dy={WorldMap.label_position(marker.name).dy}
            x={hd(marker.center) + WorldMap.label_position(marker.name).dx * viewport.scale}
            y={
              List.last(marker.center) +
                WorldMap.label_position(marker.name).dy * viewport.scale
            }
            text-anchor={WorldMap.label_position(marker.name).anchor}
            font-size={12 * viewport.scale}
            fill="#e2e8f0"
            stroke="#020617"
            stroke-width={3 * viewport.scale}
            paint-order="stroke"
            pointer-events="none"
          >
            {marker.name}
          </text>
          <text
            :if={length(marker.ports) > 1}
            x={hd(marker.center)}
            y={List.last(marker.center)}
            text-anchor="middle"
            dominant-baseline="central"
            font-size={12 * viewport.scale}
            font-weight="bold"
            fill="#0f172a"
            pointer-events="none"
          >
            {length(marker.ports)}
          </text>
        </g>
        <g :for={{id, s} <- @map_ships} data-map-ship={id}>
          <% [px, py] =
            WorldMap.project(ship_coordinates(s, @view.public["clock_ms"], @definitions.catalogue)) %>
          <circle
            cx={px}
            cy={py}
            r={4 * viewport.scale}
            vector-effect="non-scaling-stroke"
            fill="#fbbf24"
            stroke="#0f172a"
            role="button"
            tabindex="0"
            class="cursor-pointer"
            aria-label={"Inspect #{s["name"]}"}
            phx-click="inspect-ship"
            phx-value-id={id}
            phx-keydown="inspect-ship"
            phx-key="Enter"
          >
            <title>
              {s["name"]} · {@view.public["companies"][s["company_id"]]["name"]} · {@definitions.classes[
                s["class"]
              ]["name"]}
            </title>
          </circle>
        </g>
      </svg>
      <p class="px-4 pb-3 text-xs text-slate-400">
        Equal Earth map · teal: ports and regions · gold: ships at sea · ships at port appear in Port traffic
      </p>
      <div :if={@map_region} id="region-ports" class="border-t border-slate-700 p-4">
        <p class="mb-3 text-sm text-slate-300">
          Choose a port in {@map_region} to inspect its market.
        </p>
        <div class="flex flex-wrap gap-3">
          <button
            :for={name <- Enum.sort(@definitions.catalogue["clusters"][@map_region])}
            title={@definitions.catalogue["ports"][name]["harbor"]}
            phx-click="port"
            phx-value-id={name}
            aria-pressed={if name == @selected_port, do: "true", else: "false"}
            class={[
              "rounded border px-4 py-3 text-left",
              if(name == @selected_port,
                do: "border-teal-400 bg-slate-800",
                else: "border-slate-600 hover:border-teal-600"
              )
            ]}
          >
            <strong>{name}</strong><span class="block text-sm text-slate-400">{@definitions.catalogue[
              "ports"
            ][name]["harbor"]}</span>
          </button>
        </div>
      </div>
      <aside
        :if={@inspected_ship && @view.public["ships"][@inspected_ship]}
        id="map-ship-overlay"
        aria-label="Selected ship"
        class="map-ship-overlay"
      >
        <% inspected = @view.public["ships"][@inspected_ship] %>
        <% own = @view.private && @view.private["ships"][@inspected_ship] %>
        <button
          type="button"
          phx-click="close-map-ship"
          aria-label="Dismiss ship information"
          class="float-right ml-3 rounded px-2 py-1 text-slate-300"
        >✕</button>
        <h2 class="text-base font-semibold text-teal-200">{inspected["name"]}</h2>
        <p>{@view.public["companies"][inspected["company_id"]]["name"]}</p>
        <p
          :if={@view.public["companies"][inspected["company_id"]]["bankruptcy_ms"] != nil}
          class="text-red-300"
        >
          Company in bankruptcy — assets in receivership
        </p>
        <p>{@definitions.classes[inspected["class"]]["name"]} · {inspected["status"]}</p>
        <p>
          {inspected["port"]}<span :if={inspected["destination"]}> → {inspected[
            "destination"
          ]}</span>
        </p>
        <p :if={inspected["status"] in ["sailing", "loading", "unloading"]}>
          {minutes(max(0, inspected["arrive_ms"] - @view.public["clock_ms"]))} min remaining
        </p>
        <div :if={own} class="mt-2 border-t border-slate-600 pt-2">
          <p class="font-semibold">Cargo aboard</p>
          <p :if={own["cargo"] == []} class="text-slate-400">Empty hold</p>
          <table :if={own["cargo"] != []} class="w-full" aria-label="Selected ship cargo">
            <thead>
              <tr>
                <th class="text-left">Cargo</th><th class="text-right">Lots</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- manifest(own["cargo"])}>
                <td>{cargo_name(row["good"])}</td><td class="text-right tabular-nums">
                  {row["quantity"]}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </aside>
    </section>
    """
  end
end
