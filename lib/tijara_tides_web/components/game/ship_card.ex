defmodule TijaraTidesWeb.GameUI.ShipCard do
  @moduledoc "One ship's summary card, shared by the owner's fleet and the public fleet."
  use TijaraTidesWeb, :html
  import TijaraTidesWeb.GameUI.Presentation

  attr :ship, :map, required: true
  attr :definitions, :any, required: true
  attr :clock, :integer, required: true
  attr :queue_position, :any, default: nil
  attr :company, :string, default: nil
  attr :pressed, :boolean, default: false
  attr :rest, :global

  def card(assigns) do
    ~H"""
    <button
      type="button"
      aria-pressed={to_string(@pressed)}
      class={[
        "min-w-0 rounded-xl border p-3 text-left break-words",
        if(@pressed, do: "border-teal-400 bg-slate-800", else: "border-slate-700")
      ]}
      {@rest}
    >
      <strong>{@ship["name"]}</strong><p :if={@company} class="text-sm text-slate-400">
        {@company}
      </p><p>
        {l10n(@definitions.classes[@ship["class"]]["name"])} ·
        <%= if @queue_position do %>
          <span class="text-amber-300">
            {gettext("Waiting for a berth")} · {gettext("Queue position: %{position}",
              position: display_number(@queue_position)
            )}
          </span>
        <% else %>
          {l10n(@ship["status"])}
        <% end %>
      </p><p>
        {l10n(@ship["port"])}<span :if={@ship["destination"]}>{sailing_arrow()} {l10n(
          @ship["destination"]
        )}</span>
      </p>
      <p :if={@ship["arrive_ms"]} class="text-teal-300">
        {gettext("%{value1} min remaining", value1: minutes(max(0, @ship["arrive_ms"] - @clock)))}
      </p>
      <.weather_notice ship={@ship} clock={@clock} />
    </button>
    """
  end
end
