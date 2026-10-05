defmodule TijaraTidesWeb.GameUI.DepartureWait do
  use TijaraTidesWeb, :html
  alias TijaraTides.UseCases.GameQueries
  import TijaraTidesWeb.GameUI.Presentation, only: [cargo_name: 1]

  attr :ship, :map, required: true
  attr :plan, :map, default: nil
  attr :orders, :list, default: []

  def notice(assigns) do
    assigns =
      assign(
        assigns,
        :blockers,
        GameQueries.departure_wait_orders(assigns.orders, assigns.ship, assigns.plan)
      )

    ~H"""
    <div :if={@plan && @plan["departure_wait"]} class="my-2 text-sm text-amber-200">
      <%= if @blockers == [] do %>
        <p>{l10n(@plan["departure_wait"])}</p>
      <% else %>
        <div :for={order <- @blockers} class="mt-1">
          <p>
            {gettext(
              "Departure blocked: %{side} %{cargo} at %{port}, %{remaining} lots unfilled (%{filled}/%{quantity} filled).",
              side: l10n(order["side"]),
              cargo: cargo_name(order["good"]),
              port: l10n(order["port"]),
              remaining: display_number(order["quantity"] - order["filled"]),
              filled: display_number(order["filled"]),
              quantity: display_number(order["quantity"])
            )}
          </p>
          <p>{l10n(order["reason"] || "")}</p>
        </div>
        <p class="mt-1">{gettext("Fill or cancel the remaining cargo orders to depart.")}</p>
      <% end %>
    </div>
    """
  end
end
