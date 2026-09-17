defmodule TijaraTidesWeb.GameUI.AuctionPanel do
  @moduledoc "Scheduled luxury consignments and private sealed bids."
  use TijaraTidesWeb, :html
  import TijaraTidesWeb.GameUI.Presentation
  attr :definitions, :any, required: true
  attr :view, :any, required: true
  attr :port, :string, required: true
  attr :request_id, :string, required: true

  def panel(assigns) do
    assigns =
      assign(
        assigns,
        :auction,
        TijaraTides.UseCases.GameQueries.auction_options(
          assigns.definitions,
          assigns.view,
          assigns.port
        )
      )

    ~H"""
    <details
      id="luxury-auctions"
      phx-mounted={JS.ignore_attributes("open")}
      class="my-3 rounded border border-slate-700 p-2 text-sm"
    >
      <summary class="cursor-pointer font-semibold">{gettext("Cargo and ship auctions")}</summary>
      <details
        id="auction-rules"
        phx-mounted={JS.ignore_attributes("open")}
        class="my-2 text-xs text-slate-400"
      >
        <summary>{gettext("Auction rules")}</summary>
        <p>
          {gettext(
            "Sealed bids reserve the full amount and warehouse space. Highest bid wins and pays the reserve or second-highest bid, whichever is greater. Earliest bid wins ties. Revise or withdraw bids before closing; consignments lock when bidding opens. Amounts are for the whole lot. No auction fees."
          )}
        </p>
        <p>
          {gettext(
            "Countdowns use active-world time and pause while the world is stopped. Auctions settle automatically."
          )}
        </p>
      </details>
      <details id="auction-consign" phx-mounted={JS.ignore_attributes("open")} class="my-2">
        <summary>{gettext("Consign luxury cargo")}</summary>
        <p class="text-xs">
          {gettext("Next opening in %{time}", time: active_countdown(@auction.opens - @auction.clock))} · {gettext(
            "Closes in %{time}",
            time: active_countdown(@auction.closes - @auction.clock)
          )}
        </p>
        <p :if={@auction.warehouses == []}>
          {gettext("Lease compatible warehouse space at this port to place orders.")}
        </p>
        <form
          :if={@auction.warehouses != []}
          id={"auction-consign-form-" <> Base.url_encode64(@port, padding: false)}
          phx-hook="ExchangeDraft"
          phx-submit="auction"
          class="my-2 flex flex-wrap items-end gap-2"
        >
          <input type="hidden" name="action" value="auction_consign" /><input
            type="hidden"
            name="request_id"
            value={@request_id}
          />
          <label>{gettext("Cargo")}<select name="good" class="block rounded bg-slate-800 p-1"><option
            :for={{id, _} <- @auction.goods}
            value={id}
          >
            {cargo_name(id)}{if not String.contains?(@auction.roles[id] || "", "imp"),
              do: " · " <> gettext("No simulated buyers")}
          </option></select></label>
          <label>{gettext("Warehouse")}<select
            name="warehouse"
            class="block max-w-full rounded bg-slate-800 p-1"
          ><option :for={w <- @auction.warehouses} value={w["id"]}>{warehouse_name(w)}</option></select></label>
          <label>{gettext("Lots")}<input
            name="quantity"
            type="number"
            min="1"
            max="10000"
            value="1"
            required
            class="block w-20 rounded bg-slate-800 p-1"
          /></label>
          <label>{gettext("Reserve ($)")}<input
            name="price"
            type="number"
            min="1"
            step="1"
            required
            class="block w-28 rounded bg-slate-800 p-1"
          /></label>
          <button class="rounded border border-teal-700 px-2 py-1">{gettext("Consign")}</button>
        </form>
      </details>
      <p :if={@auction.listings == []} class="my-2">
        {gettext("No luxury auctions at this port yet.")}
      </p>
      <details
        :for={a <- @auction.listings}
        id={"auction-" <> a["id"]}
        phx-mounted={JS.ignore_attributes("open")}
        class="my-2 rounded border border-slate-700 p-2"
      >
        <summary class="cursor-pointer">
          {auction_name(@definitions, a)} · {display_number(a["quantity"])} {if a["ship_id"],
            do: gettext("Ship"),
            else: gettext("lots")} · {status(
            a,
            @auction.clock
          )}
        </summary>
        <p class="my-1">
          {gettext("Reserve")}: {money(a["reserve"])}
          <span :if={!a["simulated"]}>· {gettext("No simulated buyers")}</span>
        </p>
        <p :if={a["status"] == "scheduled"}>
          {gettext("Closes in %{time}", time: active_countdown(a["closes_ms"] - @auction.clock))}
        </p>
        <p :if={a["price"]}>{gettext("Sale price")}: {money(a["price"])}</p>
        <p :if={a["status"] != "scheduled" and a["amounts"] != []}>
          {gettext("Anonymous final bids")}: {Enum.map_join(a["amounts"], ", ", &money/1)}
        </p>
        <p :if={a["bid"] && a["status"] != "scheduled"}>
          {if a["bid"]["won"], do: gettext("You won"), else: gettext("No purchase")}
        </p>
        <p :if={a["bid"]}>{gettext("Your bid")}: {money(a["bid"]["amount"])}</p>
        <form
          :if={a["status"] == "scheduled" and a["mine"] and @auction.clock < a["opens_ms"]}
          phx-submit="auction"
          class="my-2 flex flex-wrap items-end gap-2"
        >
          <input type="hidden" name="request_id" value={@request_id} /><input
            type="hidden"
            name="auction"
            value={a["id"]}
          />
          <label>{gettext("Lots")}<input
            name="quantity"
            type="number"
            min="1"
            max="10000"
            value={a["quantity"]}
            class="block w-20 rounded bg-slate-800 p-1"
          /></label>
          <input type="hidden" name="price" value={dollars_input(a["reserve"])} />
          <label>{gettext("Reserve ($)")}<input
            name="reserve_dollars"
            type="number"
            min="1"
            step="1"
            value={if rem(a["reserve"], 100) == 0, do: div(a["reserve"], 100), else: ""}
            placeholder={dollars_input(a["reserve"])}
            class="block w-28 rounded bg-slate-800 p-1"
          /></label>
          <p :if={rem(a["reserve"], 100) != 0} class="text-xs text-slate-400">
            {gettext("Leave blank to keep the existing reserve.")}
          </p>
          <button
            name="action"
            value="auction_revise"
            class="rounded border border-teal-700 px-2 py-1"
          >{gettext("Update")}</button>
          <button
            name="action"
            value="auction_withdraw"
            class="rounded border border-slate-600 px-2 py-1"
          >{gettext("Withdraw consignment")}</button>
        </form>
        <form
          :if={
            a["status"] == "scheduled" and !a["mine"] and @auction.clock >= a["opens_ms"] and
              @auction.clock < a["closes_ms"] and (a["ship_id"] != nil or a["warehouses"] != [])
          }
          phx-submit="auction"
          class="my-2 flex flex-wrap items-end gap-2"
        >
          <input type="hidden" name="request_id" value={@request_id} /><input
            type="hidden"
            name="auction"
            value={a["id"]}
          />
          <label :if={is_nil(a["ship_id"])}>{gettext("Warehouse")}<select
            name="warehouse"
            class="block max-w-full rounded bg-slate-800 p-1"
          ><option
            :for={w <- a["warehouses"]}
            value={w["id"]}
            selected={a["bid"] && a["bid"]["warehouse_id"] == w["id"]}
          >
            {warehouse_name(w)}
          </option></select></label>
          <label>{gettext("Maximum bid ($)")}<input
            name="price"
            type="number"
            min={div(a["reserve"] + 99, 100)}
            step="1"
            value={div(((a["bid"] && a["bid"]["amount"]) || a["reserve"]) + 99, 100)}
            required
            class="block w-28 rounded bg-slate-800 p-1"
          /></label>
          <button name="action" value="auction_bid" class="rounded border border-teal-700 px-2 py-1">{gettext(
            "Submit sealed bid"
          )}</button>
        </form>
        <p
          :if={
            a["status"] == "scheduled" and !a["mine"] and is_nil(a["ship_id"]) and
              a["warehouses"] == []
          }
          class="text-xs text-slate-400"
        >
          {gettext(
            "The warehouse must be idle and its lease must cover auction closing. Renew or choose a longer lease."
          )}
        </p>
        <button
          :if={a["bid"] && a["status"] == "scheduled" && @auction.clock < a["closes_ms"]}
          phx-click="auction"
          phx-value-action="auction_withdraw_bid"
          phx-value-auction={a["id"]}
          phx-value-request_id={@request_id}
          class="my-1 rounded border border-slate-600 px-2 py-1"
        >{gettext("Withdraw bid")}</button>
      </details>
    </details>
    """
  end

  attr :view, :any, required: true
  attr :definitions, :any, required: true

  attr :grouping, :string, default: "status"

  def discovery(assigns) do
    assigns =
      assign(assigns,
        groups:
          TijaraTides.UseCases.GameQueries.auction_discovery(assigns.view, assigns.grouping),
        clock: get_in(assigns.view, [:public, "clock_ms"]) || 0
      )

    ~H"""
    <section id="auction-discovery" class="mb-3 rounded border border-slate-700 p-3 text-sm">
      <h3 class="font-semibold">{gettext("Cargo and ship auctions")}</h3>
      <p class="my-2 text-xs text-slate-400">
        {gettext(
          "Browse open, upcoming and recently settled auctions. Select a port to bid; compatible warehouse space is required. Reserves are for the whole lot. Times use active-world time."
        )}
      </p>
      <form id="auction-grouping" phx-change="auction-grouping" class="my-2">
        <label>
          {gettext("Group by")}
          <select name="grouping" class="rounded bg-slate-800 p-1">
            <option value="status" selected={@grouping == "status"}>{gettext("Status")}</option>
            <option value="cargo" selected={@grouping == "cargo"}>{gettext("Cargo")}</option>
          </select>
        </label>
      </form>
      <p :if={@groups == []}>{gettext("No luxury auctions available.")}</p>
      <details
        :for={{group, listings} <- @groups}
        id={"discover-auctions-" <> @grouping <> "-" <> group}
        open={@grouping == "status" and group == "open"}
        phx-mounted={JS.ignore_attributes("open")}
        class="my-2"
      >
        <summary class="cursor-pointer text-teal-300">
          {discovery_heading(@grouping, group)} · {display_number(length(listings))}
        </summary>
        <div class="max-h-64 overflow-auto">
          <table class="w-full text-sm">
            <thead>
              <tr>
                <th class="text-start">{gettext("Port")}</th><th :if={@grouping == "status"}>
                  {gettext("Cargo")}
                </th><th>{gettext("Lots")}</th><th>
                  {gettext("Reserve")}
                </th><th>{gettext("Bidding")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={a <- listings} class="border-t border-slate-800" data-auction={a["id"]}>
                <td class="py-2">
                  <button
                    type="button"
                    phx-click={
                      JS.push("auction-port", value: %{id: a["port"]})
                      |> JS.set_attribute({"open", ""}, to: "#luxury-auctions")
                    }
                    class="text-teal-300 underline"
                  >{l10n(a["port"])}</button>
                </td>
                <td :if={@grouping == "status"} class="px-2">
                  {auction_name(@definitions, a)}
                </td>
                <td class="px-2 text-end">{display_number(a["quantity"])}</td>
                <td class="px-2 text-end">{money(a["reserve"])}</td>
                <td class="py-2 text-end">
                  {status(a, @clock)}
                  <p :if={a["status"] != "scheduled" && a["bid"]}>
                    {if a["bid"]["won"], do: gettext("You won"), else: gettext("No purchase")}
                  </p>
                  <p :if={a["price"]}>{gettext("Sale price")}: {money(a["price"])}</p>
                  <br :if={a["status"] == "scheduled" && a["opens_ms"] <= @clock} /><span :if={
                    a["status"] == "scheduled" && a["opens_ms"] <= @clock
                  }>{gettext("Closes in %{time}", time: active_countdown(a["closes_ms"] - @clock))}</span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </details>
    </section>
    """
  end

  # Ship auctions carry a hull class in `good`; name it the way every other surface does.
  defp auction_name(definitions, a) do
    if a["ship_id"],
      do: l10n(definitions.classes[a["good"]]["name"] || a["good"]),
      else: cargo_name(a["good"])
  end

  defp discovery_heading("cargo", good), do: cargo_name(good)
  defp discovery_heading("status", "settled"), do: gettext("Settled auctions")
  defp discovery_heading("status", "open"), do: gettext("Open auctions")
  defp discovery_heading("status", "upcoming"), do: gettext("Upcoming auctions")

  # Preserve an existing fractional reserve when the seller only changes quantity.
  defp dollars_input(cents),
    do: "#{div(cents, 100)}.#{String.pad_leading(Integer.to_string(rem(cents, 100)), 2, "0")}"

  defp status(a, clock) do
    case a["status"] do
      "scheduled" ->
        if clock < a["opens_ms"],
          do: gettext("Opens in %{time}", time: active_countdown(a["opens_ms"] - clock)),
          else: gettext("Bidding open")

      "sold" ->
        gettext("Sold")

      "unsold" ->
        gettext("Unsold")

      "cancelled" ->
        gettext("Cancelled")
    end
  end
end
