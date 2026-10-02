defmodule TijaraTidesWeb.GameUI.ExchangePanel do
  @moduledoc "Remote standardized-cargo trading with explicit warehouse backing."
  use TijaraTidesWeb, :html
  import TijaraTidesWeb.GameUI.Presentation

  attr :side, :string, required: true
  attr :terms, :map, default: %{}
  attr :presets, :list, default: []
  attr :editing, :boolean, default: false

  def freshness_controls(assigns) do
    ~H"""
    <fieldset :if={@side == "buy"} class="flex flex-wrap gap-2">
      <label>
        {gettext("Minimum freshness grade")}
        <select name="min_grade" class="block rounded bg-slate-800 p-1">
          <option :for={grade <- 0..3} value={grade} selected={(@terms["min_grade"] || 0) == grade}>
            {freshness_grade(grade)}
          </option>
        </select>
      </label>
      <label>
        {gettext("Minimum remaining life (minutes)")}
        <input
          name="freshness_minutes"
          type="number"
          min="0"
          max="43200"
          value={div(@terms["min_remaining_ms"] || 0, 60_000)}
          class="block w-24 rounded bg-slate-800 p-1"
        />
      </label>
    </fieldset>
    <fieldset :if={@side == "sell"} class="flex flex-wrap gap-2">
      <label>
        {gettext("Automatic markdowns")}
        <select name="markdown_mode" class="block rounded bg-slate-800 p-1">
          <option :if={@editing} value="keep" selected>{gettext("Keep applied settings")}</option>
          <option value="off" selected={!@editing}>{gettext("Off")}</option>
          <option value="custom">{gettext("Use percentages below")}</option>
          <option :for={preset <- @presets} value={"preset:" <> preset["id"]}>
            {preset["name"]}
          </option>
        </select>
      </label>
      <label :for={{grade, name} <- Enum.with_index(~w(clearance fair good fresh))}>
        {freshness_grade(name)} (%)
        <input
          name={"markdowns[#{grade}]"}
          type="number"
          min="0"
          max="100"
          value={
            get_in(@terms, ["markdowns", grade]) ||
              %{"fresh" => 100, "good" => 80, "fair" => 50, "clearance" => 20}[grade]
          }
          class="block w-20 rounded bg-slate-800 p-1"
        />
      </label>
      <label>
        {gettext("Absolute price floor ($)")}
        <input
          name="price_floor"
          type="number"
          min="0"
          max="10000000000"
          value={whole_dollars(@terms["price_floor"] || 0)}
          class="block w-24 rounded bg-slate-800 p-1"
        />
      </label>
      <label :if={@editing}><input name="rebase" type="checkbox" value="true" /> {gettext(
        "Rebase percentages on the new asking price"
      )}</label>
    </fieldset>
    """
  end

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
      <summary class="cursor-pointer font-semibold">
        <.emoji symbol="💱" />{gettext("Cargo exchange")}
      </summary>
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
            {cargo_option(id)}
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
              <th>{gettext("Price")}</th><th>{gettext("Lots")}</th><th :if={@book.perishable}>
                {gettext("Freshness")}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={level <- levels}>
              <td>{money(level["price"])} {if level["npc"], do: gettext("Market maker")}</td><td>
                {display_number(level["quantity"])}
              </td>
              <td :if={@book.perishable}>
                {freshness_grade(level["grade"] || level["min_grade"])}
                <span :if={level["remaining_ms"]}>{gettext("%{minutes} mins remaining",
                  minutes: display_number(div(level["remaining_ms"], 60_000))
                )}</span>
                <span :if={(level["min_remaining_ms"] || 0) > 0}>{gettext("At least %{minutes} mins",
                  minutes: display_number(div(level["min_remaining_ms"], 60_000))
                )}</span>
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
        id={"exchange-place-" <> Base.url_encode64(Enum.join([@port, @book.good, side], "|"), padding: false)}
        phx-hook="ExchangeDraft"
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
        ><option
          :for={w <- @book.warehouses}
          :if={
            side == "sell" or (not w["award_grace"] and w["expires_ms"] > @view.public["clock_ms"])
          }
          value={w["id"]}
        >
          {display_number(w["blocks"])} {gettext("Blocks")} · {warehouse_name(w)}
        </option></select></label>
        <label>{gettext("Lots")}<input
          name="quantity"
          type="number"
          min="1"
          max="10000"
          value="1"
          class="block w-20 rounded bg-slate-800 p-1"
        /></label>
        <.freshness_controls :if={@book.perishable} side={side} presets={@book.presets} />
        <label>{gettext("Limit price per lot ($)")}<input
          name="price"
          type="number"
          min="1"
          max="10000000000"
          step="1"
          value={
            if @book.quote,
              do: whole_dollars(@book.quote[if(side == "buy", do: "ask", else: "bid")]),
              else: 1
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
        <summary class="cursor-pointer font-semibold">
          <.emoji symbol="📋" />{gettext("Your open orders")}
        </summary>
        <div :for={o <- @book.orders} class="my-2 border-t border-slate-700 py-1">
          <p>
            <.cargo_label good={o["good"]} />
            · {if o["side"] == "buy",
              do: gettext("Buy"),
              else: gettext("Sell")} · {display_number(o["quantity"])} {gettext("Lots")} · {money(
              o["price"]
            )}
          </p>
          <p :for={portion <- Map.values(o["portions"] || %{})} class="text-xs text-amber-200">
            {freshness_grade(portion["grade"])} · {display_number(portion["quantity"])} {gettext(
              "Lots"
            )} · {money(portion["price"])} · {gettext("%{minutes} mins remaining",
              minutes:
                display_number(div(max(0, portion["expires_ms"] - @view.public["clock_ms"]), 60_000))
            )}
          </p>
          <p :if={o["markdowns"]} class="text-xs text-slate-400">
            {gettext("Markdown basis: %{price}. Preset edits do not change these applied settings.",
              price: money(o["initial_price"] || o["price"])
            )}
          </p>
          <form
            id={"exchange-amend-" <> Base.url_encode64(o["id"], padding: false)}
            phx-hook="ExchangeDraft"
            phx-submit="exchange"
            class="flex flex-wrap items-end gap-2"
          >
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
              min="1"
              max="10000000000"
              step="1"
              value={whole_dollars(o["price"])}
              class="block w-28 rounded bg-slate-800 p-1"
            /></label>
            <.freshness_controls
              :if={@definitions.catalogue["goods"][o["good"]]["shelf_ms"] > 0}
              side={o["side"]}
              terms={o}
              presets={@book.presets}
              editing
            />
            <% expiry_id = "exchange-expiry-" <> Base.url_encode64(o["id"], padding: false) %>
            <label>{gettext("New expiry in minutes (optional)")}<input
              id={expiry_id}
              disabled={is_nil(o["expires_ms"])}
              name="minutes"
              type="number"
              min="1"
              class="block w-20 rounded bg-slate-800 p-1"
            /></label>
            <label><input
              type="checkbox"
              name="clear_expiry"
              value="true"
              checked={is_nil(o["expires_ms"])}
            /> {gettext("No expiry")}</label>
            <div class="flex items-center gap-2">
              <button class="rounded border border-teal-700 px-2 py-1">{gettext("Amend order")}</button>
              <button
                type="button"
                phx-click="exchange"
                phx-value-action="exchange_cancel"
                phx-value-order={o["id"]}
                phx-value-request_id={@request_id}
                class="rounded border border-slate-500 px-2 py-1"
              >{gettext("Cancel order")}</button>
            </div>
          </form>
        </div>
      </details>
      <details
        :if={@view.private}
        id="markdown-presets"
        phx-mounted={JS.ignore_attributes("open")}
        class="my-2"
      >
        <summary class="cursor-pointer">{gettext("Markdown presets")}</summary>
        <p class="text-xs text-slate-400">
          {gettext(
            "Save percentages for every grade. Apply a preset explicitly to copy its settings; editing or deleting it leaves active orders unchanged."
          )}
        </p>
        <form
          :for={preset <- [%{"id" => nil, "name" => ""} | @book.presets]}
          id={"markdown-preset-" <> (preset["id"] || "new")}
          phx-hook="ExchangeDraft"
          phx-submit="exchange"
          class="my-2 flex flex-wrap items-end gap-2"
        >
          <input type="hidden" name="action" value="markdown_preset_save" /><input
            type="hidden"
            name="request_id"
            value={@request_id}
          />
          <input :if={preset["id"]} type="hidden" name="preset" value={preset["id"]} />
          <label>{gettext("Preset name")}<input
            name="name"
            value={preset["name"]}
            maxlength="80"
            required
            class="block rounded bg-slate-800 p-1"
          /></label>
          <label :for={{grade, index} <- Enum.with_index(~w(clearance fair good fresh))}>
            {freshness_grade(index)} (%)
            <input
              type="number"
              name={"markdowns[#{grade}]"}
              min="0"
              max="100"
              required
              value={
                get_in(preset, ["markdowns", grade]) ||
                  %{"fresh" => 100, "good" => 80, "fair" => 50, "clearance" => 20}[grade]
              }
              class="block w-20 rounded bg-slate-800 p-1"
            />
          </label>
          <label>{gettext("Absolute price floor ($)")}<input
            name="price_floor"
            type="number"
            min="0"
            value={whole_dollars(preset["price_floor"] || 0)}
            class="block w-24 rounded bg-slate-800 p-1"
          /></label>
          <button class="rounded border border-teal-700 px-2 py-1">{gettext("Save preset")}</button>
          <button
            :if={preset["id"]}
            type="button"
            phx-click="exchange"
            phx-value-action="markdown_preset_delete"
            phx-value-preset={preset["id"]}
            phx-value-request_id={@request_id}
            class="rounded border border-slate-500 px-2 py-1"
          >{gettext("Delete preset")}</button>
        </form>
      </details>
      <details id="exchange-trades" phx-mounted={JS.ignore_attributes("open")} class="my-2">
        <summary class="cursor-pointer"><.emoji symbol="🤝" />{gettext("Recent trades")}</summary>
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
            "Remote trades settle into warehouses. Buys reserve limit-price cash and space; sells reserve stock. Best price, then earliest order wins; fills use the resting price. Reducing quantity keeps priority; increasing quantity or changing price resets it. No exchange fees. Market maker rows show only their current price level, shared with ship trading."
          )}
        </p>
      </details>
    </details>
    """
  end

  defp whole_dollars(cents), do: max(1, div(cents + 50, 100))
end
