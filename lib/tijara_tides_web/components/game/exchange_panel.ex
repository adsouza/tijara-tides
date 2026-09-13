defmodule TijaraTidesWeb.GameUI.ExchangePanel do
  @moduledoc "Remote standardized-cargo trading with explicit warehouse backing."
  use TijaraTidesWeb, :html
  import TijaraTidesWeb.GameUI.Presentation
  attr :definitions, :any, required: true
  attr :view, :any, required: true
  attr :port, :string, required: true
  attr :good, :any, default: nil
  attr :request_id, :string, required: true

  def panel(assigns) do
    assigns =
      assign(
        assigns,
        :book,
        TijaraTides.UseCases.GameQueries.exchange_options(
          assigns.definitions,
          assigns.view,
          assigns.port,
          assigns.good
        )
      )

    ~H"""
    <details
      id="exchange-panel"
      phx-mounted={JS.ignore_attributes("open")}
      class="my-3 rounded border border-slate-700 p-2 text-sm"
    >
      <summary class="cursor-pointer font-semibold">{gettext("Cargo exchange")}</summary>
      <form
        id="exchange-good-selector"
        phx-change="exchange-good"
        phx-hook="PortSelector"
        phx-update="ignore"
        data-selected={@book.good}
        class="my-2"
      >
        <select
          name="good"
          aria-label={gettext("Exchange cargo")}
          class="max-w-full rounded bg-slate-800 p-1"
        >
          <option :for={{id, _} <- @book.goods} value={id} selected={id == @book.good}>
            {cargo_name(id)}
          </option>
        </select>
      </form>
      <div class="grid grid-cols-2 gap-2">
        <table
          :for={{title, levels} <- [{gettext("Bids"), @book.bids}, {gettext("Asks"), @book.asks}]}
          class="w-full text-start text-xs"
        >
          <caption class="text-start font-semibold">{title}</caption>
          <thead>
            <tr>
              <th>{gettext("Price")}</th><th>{gettext("Lots")}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={level <- levels}>
              <td>{money(level["price"])} {if level["npc"], do: gettext("NPC")}</td><td>
                {display_number(level["quantity"])}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p :if={@book.warehouses == []} class="my-2 text-xs text-slate-400">
        {gettext("Lease compatible warehouse space at this port to place orders.")}
      </p>
      <form
        :for={side <- ["buy", "sell"]}
        :if={@book.warehouses != []}
        phx-submit="exchange"
        class="my-2 flex flex-wrap items-end gap-2"
      >
        <input type="hidden" name="action" value="exchange_place" /><input
          type="hidden"
          name="request_id"
          value={@request_id}
        /><input type="hidden" name="good" value={@book.good} /><input
          type="hidden"
          name="side"
          value={side}
        />
        <label>{gettext("Warehouse")}<select
          name="warehouse"
          class="block max-w-32 rounded bg-slate-800 p-1"
        ><option :for={w <- @book.warehouses} value={w["id"]}>
          {display_number(w["blocks"])} {gettext("Blocks")} · {String.slice(w["id"], 0, 6)}
        </option></select></label>
        <label>{gettext("Lots")}<input
          name="quantity"
          type="number"
          min="1"
          max="10000"
          value="1"
          class="block w-20 rounded bg-slate-800 p-1"
        /></label>
        <label>{gettext("Limit price per lot ($)")}<input
          name="price"
          type="number"
          min="0.01"
          max="10000000000"
          step="0.01"
          value={
            if @book.quote, do: @book.quote[if(side == "buy", do: "ask", else: "bid")] / 100, else: 1
          }
          class="block w-28 rounded bg-slate-800 p-1"
        /></label>
        <label>{gettext("Expires in minutes (optional)")}<input
          name="minutes"
          type="number"
          min="1"
          class="block w-20 rounded bg-slate-800 p-1"
        /></label>
        <button class="rounded bg-teal-700 px-2 py-1">{if side == "buy",
          do: gettext("Place buy order"),
          else: gettext("Place sell order")}</button>
      </form>
      <details
        :if={@book.orders != []}
        id="exchange-own-orders"
        phx-mounted={JS.ignore_attributes("open")}
        class="my-2"
      >
        <summary class="cursor-pointer font-semibold">{gettext("Your open orders")}</summary>
        <div :for={o <- @book.orders} class="my-2 border-t border-slate-700 py-1">
          <p>
            {cargo_name(o["good"])} · {if o["side"] == "buy",
              do: gettext("Buy"),
              else: gettext("Sell")} · {display_number(o["quantity"])} {gettext("Lots")} · {money(
              o["price"]
            )}
          </p>
          <form phx-submit="exchange" class="flex flex-wrap items-end gap-2">
            <input type="hidden" name="action" value="exchange_amend" /><input
              type="hidden"
              name="request_id"
              value={@request_id}
            /><input type="hidden" name="order" value={o["id"]} />
            <label>{gettext("Remaining lots")}<input
              name="quantity"
              type="number"
              min="1"
              max="10000"
              value={o["quantity"]}
              class="block w-20 rounded bg-slate-800 p-1"
            /></label>
            <label>{gettext("Limit price per lot ($)")}<input
              name="price"
              type="number"
              min="0.01"
              max="10000000000"
              step="0.01"
              value={o["price"] / 100}
              class="block w-28 rounded bg-slate-800 p-1"
            /></label>
            <label>{gettext("New expiry in minutes (optional)")}<input
              name="minutes"
              type="number"
              min="1"
              class="block w-20 rounded bg-slate-800 p-1"
            /></label>
            <label><input type="checkbox" name="clear_expiry" value="true" /> {gettext("No expiry")}</label>
            <button class="rounded border border-teal-700 px-2 py-1">{gettext("Amend order")}</button>
          </form>
          <form phx-submit="exchange" class="mt-1">
            <input type="hidden" name="action" value="exchange_cancel" /><input
              type="hidden"
              name="request_id"
              value={@request_id}
            /><input type="hidden" name="order" value={o["id"]} /><button class="rounded border border-slate-500 px-2 py-1">{gettext(
              "Cancel order"
            )}</button>
          </form>
        </div>
      </details>
      <details id="exchange-trades" phx-mounted={JS.ignore_attributes("open")} class="my-2">
        <summary class="cursor-pointer">{gettext("Recent trades")}</summary>
        <p :for={t <- @book.trades}>
          {display_number(t["quantity"])} {gettext("Lots")} · {money(t["price"])}
        </p>
      </details>
      <details
        id="exchange-terms"
        phx-mounted={JS.ignore_attributes("open")}
        class="mt-2 text-xs text-slate-400"
      >
        <summary class="cursor-pointer">{gettext("Exchange rules")}</summary><p>
          {gettext(
            "Remote trades settle into warehouses. Buys reserve limit-price cash and space; sells reserve stock. Best price, then earliest order wins; fills use the resting price. Reducing quantity keeps priority; increasing quantity or changing price resets it. No exchange fees. NPC rows show only their current price level, shared with ship trading."
          )}
        </p>
      </details>
    </details>
    """
  end
end
