defmodule TijaraTidesWeb.ShipRouteEditor do
  use TijaraTidesWeb, :html
  attr :ship, :map, required: true
  attr :model, :map, required: true
  attr :catalogue, :map, required: true
  attr :drafts, :map, default: %{}
  attr :request_id, :string, required: true

  def panel(assigns) do
    ~H"""
    <details
      id={"repeating-route-" <> @ship["id"]}
      phx-mounted={JS.ignore_attributes("open")}
      class="mt-4 rounded border border-slate-700 p-3"
    >
      <summary class="cursor-pointer font-semibold">{gettext("Repeating route")}</summary>
      <details
        id={"route-help-" <> @ship["id"]}
        phx-mounted={JS.ignore_attributes("open")}
        class="my-2 text-xs text-slate-400"
      >
        <summary class="cursor-pointer">{gettext("About repeating routes")}</summary>
        <p class="mt-2">
          {gettext(
            "Stops run in order and repeat. Cargo edits apply when that stage next runs; existing visit orders keep their terms. Current and next stops cannot be removed while active. Start at the first stop, or while sailing there. Sales finish unloading before purchases begin. A load target includes cargo already aboard; an optional purchase cap resets each visit. With no cap, purchases use available cash while keeping the voyage reserve. Prices are per lot, excluding handling; caps include handling and cleaning. No cash is earmarked. Fixed targets wait until filled or cancelled. Buy maximum stops at available capacity, stock, cash, or the purchase cap. Sell all aboard sells what current demand and buyer funds permit, then continues with unsold cargo aboard. Price limits still wait. Once sales finish, a full hold cancels any remaining loading shortfall. Pausing stops new trades and automatic departures; committed voyages and handling finish."
          )}
        </p>
      </details>
      <p :if={@model.route} class="my-2 text-sm">
        <strong>{l10n(@model.route["status"])}</strong> · {l10n(@model.route["reason"] || "")}
      </p>
      <p :if={@model.route && @model.route["stop_after"]} class="my-2 text-sm text-amber-200">
        {gettext("Will stop after this visit finishes.")}
      </p>
      <ol class="space-y-2">
        <li :for={stop <- @model.stops} class="rounded border border-slate-700 p-2 text-sm">
          <div class="flex items-center justify-between gap-2">
            <strong>{stop["position"] + 1}. {l10n(stop["port"])}<span
              :if={@model.route["status"] != "draft" && @model.route["cursor"] == stop["position"]}
              class="ml-2 text-teal-200"
            >{gettext("Selected stop")}</span></strong>
            <button
              type="button"
              phx-click="route"
              phx-value-operation="remove_stop"
              disabled={
                @model.route["status"] != "draft" &&
                  stop["position"] in [
                    @model.route["cursor"],
                    rem(@model.route["cursor"] + 1, length(@model.stops))
                  ]
              }
              title={gettext("Current and next stops are protected while the route is active")}
              phx-value-stop={stop["id"]}
              phx-value-request_id={@request_id}
              class="rounded border px-2 py-1"
            >{gettext("Remove stop")}</button>
          </div>
          <p :for={rule <- Map.get(@model.rules, stop["id"], [])} class="mt-2">
            {gettext("%{value1} %{value2} · %{value3} $%{value4} / lot",
              value1:
                if(rule["quantity_mode"] == "maximum",
                  do:
                    if(rule["side"] == "buy",
                      do: gettext("Buy maximum"),
                      else: gettext("Sell all aboard")
                    ),
                  else:
                    if(rule["side"] == "buy",
                      do:
                        gettext("Load up to %{lots} lots of", lots: display_number(rule["quantity"])),
                      else:
                        gettext("Sell up to %{lots} lots of", lots: display_number(rule["quantity"]))
                    )
                ),
              value2: l10n(@catalogue["goods"][rule["good"]]["name"]),
              value3: if(rule["side"] == "buy", do: gettext("max"), else: gettext("min")),
              value4: TijaraTides.Localization.number(rule["limit"] / 100, format: "0.00")
            )}
            <span :if={rule["side"] == "buy" && rule["budget"]}>
              {gettext("· cap $%{value1}",
                value1: TijaraTides.Localization.number(rule["budget"] / 100, format: "0.00")
              )}
            </span>
            <button
              type="button"
              phx-click={
                JS.push("route-edit-rule")
                |> JS.set_attribute({"open", ""}, to: "#route-targets-" <> stop["id"])
              }
              phx-value-rule={rule["id"]}
              class="ml-2 rounded border px-2"
            >{gettext("Edit")}</button>
            <button
              type="button"
              phx-click="route"
              phx-value-operation="remove_rule"
              phx-value-rule={rule["id"]}
              phx-value-request_id={@request_id}
              class="ml-2 rounded border px-2"
            >{gettext("Remove")}</button>
          </p>
          <details
            id={"route-targets-" <> stop["id"]}
            phx-mounted={JS.ignore_attributes("open")}
            class="mt-2"
          >
            <summary class="cursor-pointer">
              {if @drafts[stop["id"]] && @drafts[stop["id"]]["rule"],
                do: gettext("Edit cargo target"),
                else: gettext("Add cargo target")}
            </summary>
            <% draft = Map.get(@drafts, stop["id"], %{}) %>
            <% side = if draft["side"] == "sell", do: "sell", else: "buy" %>
            <% goods = @model.stop_goods[stop["id"]][side] %>
            <div id={"route-editor-" <> stop["id"] <> "-" <> (draft["rule"] || "new")}>
              <.form
                for={%{}}
                id={"route-rule-" <> stop["id"]}
                phx-submit="route"
                phx-change="route-draft"
                class="mt-2 grid grid-cols-2 gap-2"
              >
                <input
                  type="hidden"
                  name="operation"
                  value={if draft["rule"], do: "update_rule", else: "add_rule"}
                />
                <input :if={draft["rule"]} type="hidden" name="rule" value={draft["rule"]} />
                <input type="hidden" name="stop" value={stop["id"]} />
                <input type="hidden" name="request_id" value={@request_id} />
                <label>{gettext("Action")}<select
                  name="side"
                  class="block w-full rounded bg-slate-800 p-2"
                ><option
                  value="buy"
                  selected={side == "buy"}
                >
                  {gettext("Buy / load target")}
                </option><option value="sell" selected={side == "sell"}>
                  {gettext("Sell up to")}
                </option></select></label>
                <label>{gettext("Cargo")}
                <select
                  name="good"
                  disabled={goods == []}
                  class="block w-full rounded bg-slate-800 p-2"
                >
                  <option :if={goods == []} value="">{gettext("No compatible cargo")}</option><option
                    :for={{id, good} <- goods}
                    value={id}
                    selected={draft["good"] == id}
                  >
                    {l10n(good["name"])}
                  </option>
                </select></label>
                <label>{gettext("Quantity")}
                <select
                  name="quantity_mode"
                  class="block w-full rounded bg-slate-800 p-2"
                >
                  <option value="fixed" selected={draft["quantity_mode"] != "maximum"}>
                    {gettext("Fixed lots")}
                  </option>
                  <option value="maximum" selected={draft["quantity_mode"] == "maximum"}>
                    {if side == "buy", do: gettext("Buy maximum"), else: gettext("Sell all aboard")}
                  </option>
                </select></label>
                <label>{gettext("Target lots")}<input
                  disabled={draft["quantity_mode"] == "maximum"}
                  name="quantity"
                  type="number"
                  required
                  min="1"
                  max="10000"
                  value={draft["quantity"] || "1"}
                  class="block w-full rounded bg-slate-800 p-2"
                /></label>
                <label>{if side == "buy",
                  do: gettext("Maximum price / lot ($)"),
                  else: gettext("Minimum price / lot ($)")}<input
                  name="limit"
                  type="number"
                  required
                  min="0"
                  max="10000000000"
                  step="0.01"
                  value={draft["limit"]}
                  class="block w-full rounded bg-slate-800 p-2"
                /></label>
                <label>{gettext("Purchase cap ($, optional)")}<input
                  name="budget"
                  placeholder={gettext("No cap")}
                  type="number"
                  disabled={side == "sell"}
                  min="1"
                  max="10000000000"
                  value={draft["budget"]}
                  class="block w-full rounded bg-slate-800 p-2 disabled:opacity-40"
                /></label>
                <button
                  disabled={goods == []}
                  class="self-end rounded bg-teal-600 px-3 py-2 disabled:opacity-40"
                >{if draft["rule"], do: gettext("Save target"), else: gettext("Add target")}</button>
                <button
                  :if={draft["rule"]}
                  type="button"
                  phx-click="route-edit-cancel"
                  phx-value-stop={stop["id"]}
                  class="rounded border px-3 py-2"
                >{gettext("Cancel edit")}</button>
              </.form>
            </div>
          </details>
        </li>
      </ol>
      <p :if={length(@model.stops) > 1} class="my-2 text-xs text-slate-400">
        {gettext("After the final stop, return to %{value1}.", value1: l10n(hd(@model.stops)["port"]))}
      </p>
      <.form
        for={%{}}
        id={"route-stop-" <> @ship["id"]}
        phx-submit="route"
        class="my-3 flex flex-wrap items-end gap-2 text-sm"
      >
        <input type="hidden" name="operation" value="add_stop" /><input
          type="hidden"
          name="request_id"
          value={@request_id}
        />
        <label>{gettext("Port")}<select name="port" class="ml-2 rounded bg-slate-800 p-2"><option
          :for={port <- Enum.sort(Map.keys(@catalogue["ports"]))}
          value={port}
          selected={port == (@ship["destination"] || @ship["port"])}
        >
          {l10n(port)}
        </option></select></label>
        <button
          disabled={
            length(@model.stops) >= 8 ||
              (@model.route && @model.route["status"] != "draft" && @model.route["phase"] != "arrival" &&
                 @model.route["cursor"] == length(@model.stops) - 1)
          }
          class="rounded bg-teal-600 px-3 py-2 disabled:opacity-40"
        >{gettext("Add stop")}</button>
      </.form>
      <.form
        :if={@model.route && @model.route["status"] != "running" && length(@model.stops) >= 2}
        for={%{}}
        id={"route-start-" <> @ship["id"]}
        phx-submit="route"
        class="my-3 flex flex-wrap items-center gap-2 text-sm"
      >
        <input
          type="hidden"
          name="operation"
          value={if @model.route["status"] == "draft", do: "start", else: "resume"}
        /><input type="hidden" name="request_id" value={@request_id} />
        <input type="hidden" name="auto_depart" value="true" />
        <span class="text-xs text-slate-400">{gettext(
          "Ships continue automatically after trades and handling finish."
        )}</span>
        <button class="rounded bg-teal-600 px-3 py-2">{if @model.route["status"] == "draft",
          do: gettext("Start route"),
          else: gettext("Resume route")}</button>
      </.form>
      <div :if={@model.route} class="my-2 flex flex-wrap gap-2 text-sm">
        <button
          :if={@model.route["status"] == "running"}
          phx-click="route"
          phx-value-operation="pause"
          phx-value-request_id={@request_id}
          class="rounded border px-2 py-1"
        >{gettext("Pause route")}</button>
        <button
          :if={@model.route["status"] == "running" && !@model.route["stop_after"]}
          phx-click="route"
          phx-value-operation="stop_after"
          phx-value-request_id={@request_id}
          class="rounded border px-2 py-1"
        >{gettext("Stop after this visit")}</button>
        <button
          phx-click="route"
          phx-value-operation="delete"
          phx-value-request_id={@request_id}
          data-confirm={
            gettext(
              "Remove this route and cancel its unfilled orders? Cargo, committed voyages and handling are preserved."
            )
          }
          class="rounded border px-2 py-1"
        >{gettext("Remove route")}</button>
      </div>
      <p :if={@model.plan && @model.plan["departure_wait"]} class="my-2 text-sm text-amber-200">
        {l10n(@model.plan["departure_wait"])}
      </p>
      <div :for={order <- @model.orders} class="mt-2 text-sm">
        {gettext("%{value1} %{value2}: %{value3}/%{value4} lots · %{value5}",
          value1: l10n(order["side"]),
          value2: l10n(@catalogue["goods"][order["good"]]["name"]),
          value3: display_number(order["filled"]),
          value4: display_number(order["quantity"]),
          value5: l10n(order["reason"] || "")
        )}
        <button
          :if={order["status"] in ["planned", "waiting"]}
          phx-click="cancel-instruction"
          phx-value-id={order["id"]}
          class="ml-2 rounded border px-2 py-1"
        >{gettext("Cancel order")}</button>
      </div>
    </details>
    """
  end
end
