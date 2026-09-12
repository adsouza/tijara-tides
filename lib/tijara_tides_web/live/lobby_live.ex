defmodule TijaraTidesWeb.LobbyLive do
  use TijaraTidesWeb, :live_view
  alias TijaraTides.UseCases.Game

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe before reading so a concurrent update cannot be missed.
    if connected?(socket), do: Game.presence_subscribe("ocean")
    {:ok, assign(socket, page_title: "Harbor lobby", snapshot: Game.presence_snapshot())}
  end

  @impl true
  def handle_info({:world_updated, snapshot}, socket) do
    if is_map(socket.assigns.snapshot) and
         snapshot.world_id == socket.assigns.snapshot.world_id and
         snapshot.revision > socket.assigns.snapshot.revision do
      {:noreply, assign(socket, :snapshot, snapshot)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="mx-auto max-w-5xl px-6 py-16 sm:py-24">
        <p class="text-xs font-semibold uppercase tracking-[0.3em] text-teal-300">
          A shared world awaits
        </p>
        <h1 class="mt-5 text-5xl font-semibold tracking-tight sm:text-7xl">Tijara Tides</h1>
        <p class="mt-6 max-w-3xl text-lg leading-8 text-slate-300">
          An ocean of possibilities. A multiplayer marine trading game, beginning here.
        </p>
        <div class="mt-12 rounded-2xl border border-slate-700 bg-slate-900/70 p-8">
          <div class="flex flex-wrap items-center justify-between gap-4">
            <h2 class="text-xl font-medium">Harbor lobby</h2>
            <span id="connection-status" class="text-sm text-teal-300">
              <span class="phx-connected:hidden">Connecting…</span>
              <span class="hidden phx-connected:inline">Live player count</span>
            </span>
          </div>
          <dl class="mt-8">
            <div>
              <dt class="text-sm text-slate-400">Players online</dt><dd
                id="online-players"
                class="mt-2 text-4xl"
              >
                {@snapshot.online_players}
              </dd>
            </div>
          </dl>
        </div>
        <a href="/play" class="mt-8 inline-block rounded-lg bg-teal-700 px-6 py-3 text-white">Explore the trading world</a>
      </section>
    </Layouts.app>
    """
  end
end
