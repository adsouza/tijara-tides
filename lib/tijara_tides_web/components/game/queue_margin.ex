defmodule TijaraTidesWeb.GameUI.QueueMargin do
  @moduledoc "Asks for the price margin a manual trade waits with when it must be queued."
  use TijaraTidesWeb, :html

  import TijaraTidesWeb.GameUI.Presentation, only: [finance_money: 1, cargo_name: 1]
  alias TijaraTides.UseCases.GameQueries

  attr :prompt, :map, required: true

  def dialog(assigns) do
    command = assigns.prompt.command
    side = command["action"]
    per_lot = GameQueries.queued_limit(side, command["limit"], assigns.prompt.margin_bps)

    assigns =
      assign(assigns,
        side: side,
        # The trade form that opened the dialog, for returning keyboard focus to it.
        origin: "trade-#{side}-#{String.replace(command["good"], " ", "-")}",
        good: command["good"],
        per_lot: per_lot,
        total: per_lot * command["quantity"]
      )

    ~H"""
    <div id="queue-margin-backdrop" class="destination-picker-backdrop">
      <.focus_wrap id="queue-margin-focus">
        <section
          id="queue-margin-dialog"
          role="dialog"
          aria-modal="true"
          aria-labelledby="queue-margin-title"
          aria-describedby="queue-margin-help"
          class="queue-margin-dialog"
          phx-window-keydown="queue-margin-cancel"
          phx-key="Escape"
          phx-click-away="queue-margin-cancel"
          phx-mounted={JS.focus_first(to: "#queue-margin-dialog")}
          phx-remove={
            JS.focus_first(to: "#port-market-" <> @side)
            |> JS.focus(to: "[id='#{@origin}'] button")
          }
        >
          <h2 id="queue-margin-title" class="text-lg font-semibold">
            {gettext("Allow a price margin?")}
          </h2>
          <p id="queue-margin-help" class="mt-2 text-sm text-slate-300">
            {gettext(
              "This ship can't trade right now, so the order will wait in the queue. Prices often move a little meanwhile, and an order at exactly today's price would then sit unfilled. A margin lets it go through; you still pay (or receive) the market price when it executes."
            )}
          </p>
          <form
            id="queue-margin-form"
            phx-change="queue-margin-change"
            phx-submit="queue-margin-confirm"
            class="mt-4 grid gap-3"
          >
            <%!-- Names the retained command's action for form inventories; the handler
                  resends the retained command and ignores this field. --%>
            <input
              type="hidden"
              name="action"
              value={if(@side == "sell", do: "sell", else: "buy")}
            />
            <label class="grid gap-1">
              <span class="flex justify-between text-sm">
                <span>{gettext("Margin")}</span>
                <span class="tabular-nums">{percent(@prompt.margin_bps)}</span>
              </span>
              <input
                type="range"
                name="margin_bps"
                min="0"
                max="1000"
                step="50"
                value={@prompt.margin_bps}
                aria-label={gettext("Queued trade margin")}
                aria-valuetext={percent(@prompt.margin_bps)}
                class="w-full accent-teal-400"
              />
            </label>
            <p id="queue-margin-worst-case" class="text-sm tabular-nums text-slate-300">
              {if @side == "buy",
                do:
                  gettext("Up to %{price} per lot of %{cargo}, %{total} in total before handling",
                    price: finance_money(@per_lot),
                    cargo: cargo_name(@good),
                    total: finance_money(@total)
                  ),
                else:
                  gettext(
                    "At least %{price} per lot of %{cargo}, %{total} in total before handling",
                    price: finance_money(@per_lot),
                    cargo: cargo_name(@good),
                    total: finance_money(@total)
                  )}
            </p>
            <label class="flex items-center gap-2 text-sm">
              <input type="checkbox" name="save_margin" value="true" checked={@prompt.save} />
              {if @side == "buy",
                do: gettext("Use this margin for all future queued buys"),
                else: gettext("Use this margin for all future queued sells")}
            </label>
            <div class="flex justify-end gap-2">
              <button type="button" phx-click="queue-margin-cancel" class="rounded border px-3 py-1">
                {gettext("Cancel")}
              </button>
              <button type="submit" class="rounded bg-teal-700 px-3 py-1">
                {gettext("Queue trade")}
              </button>
            </div>
          </form>
        </section>
      </.focus_wrap>
    </div>
    """
  end

  attr :account, :map, required: true

  @doc "The saved per-side defaults, each editable or returned to asking every time."
  def defaults(assigns) do
    ~H"""
    <section id="queue-margin-defaults" class="mt-3 text-sm text-slate-300">
      <details>
        <summary class="cursor-pointer">
          {gettext("Queued-trade margin: buys %{buy} · sells %{sell}",
            buy: label(@account["queue_margin_buy_bps"]),
            sell: label(@account["queue_margin_sell_bps"])
          )}
        </summary>
        <p class="mt-1 text-xs text-slate-400">
          {gettext(
            "A trade that has to wait for handling or a berth can fill at a price this much worse than the quote. Without a saved margin you are asked each time."
          )}
        </p>
        <div
          :for={
            {side, bps} <- [
              {"buy", @account["queue_margin_buy_bps"]},
              {"sell", @account["queue_margin_sell_bps"]}
            ]
          }
          class="mt-2 flex flex-wrap items-center gap-2"
        >
          <form
            id={"queue-margin-default-" <> side}
            phx-submit="queue-margin-save"
            class="flex flex-wrap items-center gap-2"
          >
            <input type="hidden" name="side" value={side} />
            <label class="flex items-center gap-2">
              {if side == "buy", do: gettext("Buys"), else: gettext("Sells")}
              <input
                type="range"
                name="margin_bps"
                min="0"
                max="1000"
                step="50"
                value={bps || 200}
                aria-valuetext={percent(bps || 200)}
                aria-label={
                  if side == "buy",
                    do: gettext("Default margin for queued buys"),
                    else: gettext("Default margin for queued sells")
                }
                class="accent-teal-400"
              />
            </label>
            <button class="rounded border px-2 py-0.5">{gettext("Save")}</button>
          </form>
          <button
            :if={bps}
            id={"queue-margin-reset-" <> side}
            type="button"
            phx-click="queue-margin-reset"
            phx-value-side={side}
            class="rounded border px-2 py-0.5"
          >
            {gettext("Ask me each time")}
          </button>
        </div>
      </details>
    </section>
    """
  end

  defp label(nil), do: gettext("Ask me")
  defp label(bps), do: percent(bps)

  @doc "A margin in basis points as a percentage with one decimal, e.g. 2.0%."
  def percent(bps),
    do:
      gettext("%{value}%",
        value: TijaraTides.Localization.number(bps / 100, format: "0.0")
      )
end
