defmodule TijaraTidesWeb.GameUI.QueuedDeparture do
  use TijaraTidesWeb, :html

  attr :ship, :map, required: true
  attr :private, :map, required: true
  attr :destination, :any, required: true
  attr :request_id, :string, required: true

  def panel(assigns) do
    plan =
      get_in(assigns.private, ["visit_plans", assigns.ship["id"] <> "|" <> assigns.ship["port"]])

    assigns =
      assign(assigns,
        plan: plan,
        queued: plan && plan["auto_depart"] == true,
        route: get_in(assigns.private, ["ship_routes", assigns.ship["id"]])
      )

    ~H"""
    <div
      :if={!@route && @ship["status"] in ["docked", "loading", "unloading"]}
      id="queued-departure"
      class="mt-3 text-sm"
    >
      <div :if={@queued} class="mb-2 rounded border border-teal-700 p-3">
        <p>{gettext("Queued departure to %{port}", port: l10n(@plan["onward"]))}</p>
        <p class="text-xs text-slate-400">
          {gettext(
            "Waits for all orders and handling to finish. Fuel and canal fees are checked and charged at departure."
          )}
        </p>
        <p :if={@plan["departure_wait"]} class="text-amber-300">{l10n(@plan["departure_wait"])}</p>
        <.form for={%{}} id="cancel-queued-departure" phx-submit="instruction-onward">
          <input type="hidden" name="port" value={@ship["port"]} />
          <input type="hidden" name="onward" value={@plan["onward"]} />
          <input type="hidden" name="auto_depart" value="false" />
          <input type="hidden" name="request_id" value={@request_id} />
          <button class="mt-2 rounded border px-3 py-1">{gettext("Cancel queued departure")}</button>
        </.form>
      </div>
      <.form
        :if={
          @ship["status"] in ["loading", "unloading"] && @destination not in [nil, "", @ship["port"]] &&
            (!@queued || @plan["onward"] != @destination)
        }
        for={%{}}
        id="queue-departure"
        phx-submit="instruction-onward"
      >
        <input type="hidden" name="port" value={@ship["port"]} />
        <input type="hidden" name="onward" value={@destination} />
        <input type="hidden" name="auto_depart" value="true" />
        <input type="hidden" name="request_id" value={@request_id} />
        <button class="rounded border border-teal-700 px-3 py-2 text-teal-200">
          {gettext("Sail to %{port} after handling", port: l10n(@destination))}
        </button>
        <p class="mt-1 text-xs text-slate-400">
          {gettext(
            "Waits for all orders and handling to finish. Fuel and canal fees are checked and charged at departure."
          )}
        </p>
      </.form>
    </div>
    """
  end
end
