defmodule TijaraTidesWeb.GameUI.MusicPanel do
  @moduledoc """
  Header music controls. GameLive owns `music_focus`, the player's latest
  explicit ship or port selection; this component renders the musical context
  that focus implies, which the client's Music hook follows.
  """
  use TijaraTidesWeb, :html
  alias TijaraTides.UseCases.GameQueries

  attr :view, :any, required: true
  attr :focus, :any, required: true

  def panel(assigns) do
    assigns =
      assign(assigns,
        context: context(assigns.view, assigns.focus),
        available: TijaraTidesWeb.Music.status() == :available
      )

    ~H"""
    <div
      id="music"
      phx-hook="Music"
      class="music-control"
      data-music={if @available, do: "available", else: "unavailable"}
      data-manifest={TijaraTidesWeb.Music.manifest_url()}
      data-context={@context["context"]}
      data-port={@context["port"]}
      data-ship={@context["ship"]}
      data-origin={@context["origin"]}
      data-destination={@context["destination"]}
      data-progress={@context["progress"]}
      data-now-playing={
        gettext("Now playing: %{title} by %{artists}", title: "%{title}", artists: "%{artists}")
      }
    >
      <div id="music-controls" class="music-controls" phx-update="ignore" hidden={!@available}>
        <button
          type="button"
          id="music-toggle"
          class="popup-menu-trigger"
          aria-pressed="true"
          aria-label={gettext("Music")}
        >🔊</button>
        <details id="music-settings" class="music-settings">
          <summary class="popup-menu-trigger" aria-label={gettext("Music settings")}>♪</summary>
          <div class="music-popover">
            <label for="music-volume">{gettext("Music volume")}</label>
            <input id="music-volume" type="range" min="0" max="100" step="1" value="30" />
            <a href={~p"/music/credits"} target="_blank" rel="noopener" class="underline">
              {gettext("Music credits")}
            </a>
          </div>
        </details>
        <div aria-live="polite">
          <a
            id="music-credit"
            class="music-credit"
            hidden
            target="_blank"
            rel="noopener noreferrer"
            dir="auto"
          ></a>
        </div>
      </div>
    </div>
    """
  end

  @doc "The retained focus after a view refresh."
  def focus(nil, _view, port), do: {:port, port}

  def focus({:ship, id} = focus, view, port),
    do: if(ship(view, id), do: focus, else: {:port, port})

  def focus(focus, _view, _port), do: focus

  def context(_view, {:port, port}), do: %{"context" => "port", "port" => port}

  def context(view, {:ship, id}) do
    case ship(view, id) do
      %{"status" => "sailing"} = ship ->
        progress =
          ship |> GameQueries.voyage_progress(view.public["clock_ms"]) |> max(0.0) |> min(1.0)

        %{
          "context" => "voyage",
          "ship" => id,
          "origin" => ship["port"],
          "destination" => ship["destination"],
          "progress" => :erlang.float_to_binary(progress * 1.0, decimals: 4)
        }

      %{} = ship ->
        %{"context" => "port", "port" => ship["port"]}

      nil ->
        %{}
    end
  end

  def ship(view, id), do: (view.private && view.private["ships"][id]) || view.public["ships"][id]
end
