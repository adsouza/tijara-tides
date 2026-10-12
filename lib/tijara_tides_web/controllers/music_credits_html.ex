defmodule TijaraTidesWeb.MusicCreditsHTML do
  use TijaraTidesWeb, :html

  def show(assigns) do
    ~H"""
    <main id="music-credits" class="mx-auto max-w-3xl p-6">
      <h1 class="text-2xl font-semibold">{gettext("Music credits")}</h1>
      <p class="mt-2 text-sm text-slate-300">{gettext("The soundtrack uses these recordings.")}</p>
      <article
        :for={track <- @tracks}
        id={"music-credit-" <> track.slug}
        class="mt-6 rounded-xl border border-slate-700 p-4"
      >
        <h2 class="text-lg" dir="auto">{track.title}</h2>
        <dl class="mt-2 grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-sm">
          <dt>{gettext("Credited creators")}</dt>
          <dd dir="auto">{track.credit}</dd>
          <dt>{gettext("Source")}</dt>
          <dd>
            <a class="underline" href={track.source_url} rel="noopener noreferrer">{track.source_url}</a>
          </dd>
          <dt>{gettext("License")}</dt>
          <dd>
            <a class="underline" href={track.licence_url} rel="noopener noreferrer">{track.licence}</a>
          </dd>
          <dt>{gettext("Edits")}</dt>
          <dd>{track.edits}</dd>
          <%= if track.notices != [] do %>
            <dt>{gettext("Supplied notice")}</dt>
            <dd>
              <a :for={notice <- track.notices} class="underline" href={notice.url}>{notice.name}</a>
            </dd>
          <% end %>
        </dl>
      </article>
      <a href={~p"/play"} class="mt-8 inline-block underline">{gettext("Back to the game")}</a>
    </main>
    """
  end
end
