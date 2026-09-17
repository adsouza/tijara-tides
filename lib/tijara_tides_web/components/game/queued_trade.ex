defmodule TijaraTidesWeb.GameUI.QueuedTrade do
  use TijaraTidesWeb, :html

  import TijaraTidesWeb.GameUI.Presentation,
    only: [finance_money: 1, cargo_name: 1, error_message: 1]

  attr :reason, :any, default: nil
  attr :id, :string, required: true
  attr :ship, :map, required: true
  attr :public, :map, required: true

  def notice(assigns) do
    assigns =
      assign(assigns,
        berth: get_in(assigns.public, ["berths", assigns.ship["port"]]),
        position: get_in(assigns.public, ["ships", assigns.ship["id"], "queue_position"])
      )

    ~H"""
    <div id={@id} class="my-3 rounded border border-amber-700 bg-amber-950/20 p-3 text-sm">
      <h3 class="font-semibold text-amber-200">
        {gettext("Queued trade · %{ship} · %{port}", ship: @ship["name"], port: l10n(@ship["port"]))}
      </h3>
      <p class="mt-1">
        {if @ship["pending_side"] == "sell",
          do:
            gettext("Sell %{quantity} lots of %{cargo} at no less than %{price} per lot.",
              quantity: display_number(@ship["pending_quantity"]),
              cargo: cargo_name(@ship["pending_good"]),
              price: finance_money(@ship["pending_limit"])
            ),
          else:
            gettext("Buy %{quantity} lots of %{cargo} at no more than %{price} per lot.",
              quantity: display_number(@ship["pending_quantity"]),
              cargo: cargo_name(@ship["pending_good"]),
              price: finance_money(@ship["pending_limit"])
            )}
      </p>
      <p>
        <%= case @reason do %>
          <% :handling -> %>
            {gettext("Waiting for the current loading or unloading to finish.")}
          <% :buyer_budget -> %>
            {gettext(
              "Waiting for the buyer to afford the full order; free berths cannot resolve this."
            )}
          <% reason when reason in [nil, :berth_wait] -> %>
            {gettext(
              "Waiting for berth admission. A ready order starts as soon as capacity and queue priority allow."
            )}
          <% reason -> %>
            {gettext("Waiting for trade conditions: %{reason}", reason: error_message(reason))}
        <% end %>
      </p>
      <p :if={@berth}>
        {gettext("Berths in use: %{used} / %{total}.",
          used: display_number(@berth["occupied"]),
          total: display_number(@berth["capacity"])
        )}
        <span :if={@position}>{gettext("Queue position: %{position}",
          position: display_number(@position)
        )}</span>
      </p>
      <p class="mt-1 text-xs text-slate-400">
        {gettext(
          "This order retries automatically. Price, cargo, demand and funds must still allow the full quantity. Cancel it before placing another trade or departing."
        )}
      </p>
      <button
        type="button"
        phx-click="cancel-berth-trade"
        phx-value-id={@ship["id"]}
        class="mt-2 rounded border px-3 py-1"
      >
        {gettext("Cancel queued trade")}
      </button>
    </div>
    """
  end
end
