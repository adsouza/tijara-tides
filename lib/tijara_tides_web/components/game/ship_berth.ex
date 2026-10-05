defmodule TijaraTidesWeb.GameUI.ShipBerth do
  @moduledoc "Owner-only illustrative berth scene; committed ship state controls handling."
  use TijaraTidesWeb, :html

  attr :ship, :map, required: true
  attr :clock, :integer, required: true
  attr :queue_position, :any, default: nil
  attr :liquid, :boolean, default: false
  attr :cargo_volume_l, :integer, default: 0
  attr :capacity_l, :integer, default: 1

  def scene(assigns) do
    ~H"""
    <figure
      id={"ship-berth-" <> @ship["id"]}
      phx-hook="ShipBerth"
      data-scene-src={~p"/assets/js/berth_scene.js"}
      data-status={@ship["status"]}
      data-clock={@clock}
      data-complete={@ship["arrive_ms"]}
      data-start={@ship["handling_started_ms"]}
      data-volume={@ship["handling_volume_l"]}
      data-cargo-volume={@cargo_volume_l}
      data-capacity={@capacity_l}
      data-queued={to_string(!!@queue_position)}
      data-liquid={to_string(@liquid)}
      data-laden={to_string((@ship["cargo"] || []) != [])}
      class="my-3 overflow-hidden rounded-xl border border-slate-700 bg-slate-950"
    >
      <div
        id={"ship-berth-canvas-" <> @ship["id"]}
        phx-update="ignore"
        data-berth-canvas
        class="relative h-52 sm:h-64"
        aria-hidden="true"
      >
        <svg data-berth-fallback viewBox="0 0 640 240" class="h-full w-full" focusable="false">
          <rect width="640" height="240" fill="#0b1729" />
          <path d="M0 155H640V240H0Z" fill="#164456" />
          <path d="M0 140H640" stroke="#2a6573" stroke-width="2" />
          <path d="M60 100H580V133H60Z" fill="#475569" />
          <path :if={!@liquid} d="M362 100V30H380V100M345 30H525V40H345Z" fill="#d6a958" />
          <path :if={!@liquid} d="M495 40V130" stroke="#a8bdc8" stroke-width="2" />
          <path d="M115 151H525L490 199H150Z" fill="#247b82" />
          <path d="M155 110H213V150H155Z" fill="#cbd5e1" />
          <path d="M165 120H204" stroke="#334155" stroke-width="8" />
          <path
            :if={!@liquid && (@ship["cargo"] || []) != []}
            d="M252 130H318V151H252ZM326 130H392V151H326Z"
            fill="#c39556"
          />
          <path :if={@liquid} d="M252 133H318V151H252ZM326 133H392V151H326Z" fill="#94a3b8" />
          <path
            :if={@liquid}
            d="M380 105Q430 100 430 125T380 145"
            fill="none"
            stroke="#94a3b8"
            stroke-width="4"
          />
        </svg>
      </div>
      <figcaption class="flex flex-wrap items-center justify-between gap-2 px-3 py-2 text-xs">
        <span>
          <span class="text-slate-300">{gettext("Berth view")} · {l10n(@ship["port"])}</span>
          <span class="ml-2 text-teal-300">
            {if @queue_position, do: gettext("Waiting for a berth"), else: l10n(@ship["status"])}
          </span>
        </span>
        <button
          type="button"
          data-berth-toggle
          data-pause-label={gettext("Pause animation")}
          data-resume-label={gettext("Resume animation")}
          aria-pressed="false"
          class="rounded border border-slate-600 px-2 py-1 text-slate-300 hover:border-teal-400 focus-visible:outline-2 focus-visible:outline-teal-300"
          hidden
        >
          {gettext("Pause animation")}
        </button>
        <span data-berth-unavailable class="text-slate-400" hidden>
          {gettext("Static berth view")}
        </span>
      </figcaption>
    </figure>
    """
  end
end
