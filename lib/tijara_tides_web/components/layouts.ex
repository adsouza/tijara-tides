defmodule TijaraTidesWeb.Layouts do
  use TijaraTidesWeb, :html
  embed_templates "layouts/*"

  attr :return_to, :string, default: "/play"

  def language_selector(assigns) do
    ~H"""
    <form action="/locale" method="post" class="flex items-center gap-2 my-2">
      <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
      <input type="hidden" name="return_to" value={@return_to} />
      <label for="language-choice">{gettext("Language")}</label>
      <select id="language-choice" name="locale" class="rounded bg-slate-800 p-1" dir="auto">
        <option
          :for={{code, name} <- TijaraTides.Localization.locales()}
          value={code}
          selected={code == TijaraTides.Localization.locale()}
        >
          {l10n(name)}
        </option>
      </select>
      <button class="rounded border p-1">{gettext("Apply")}</button>
    </form>
    """
  end

  attr :flash, :map, required: true
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <main
      id="localized-content"
      phx-hook="Locale"
      data-game-title={gettext("Tijara Tides")}
      data-locale={TijaraTides.Localization.locale()}
      data-direction={TijaraTides.Localization.direction(TijaraTides.Localization.locale())}
      class="min-h-screen"
    >
      {render_slot(@inner_block)}
    </main>
    <div class="fixed bottom-4 left-4 right-4 z-50 flex max-w-md flex-col gap-3 pointer-events-none">
      <div
        :for={{kind, message} <- @flash}
        role="alert"
        class="pointer-events-auto flex items-start gap-4 rounded border border-slate-600 bg-slate-800 p-4 text-slate-100 shadow-lg"
        id={"flash-#{kind}"}
        phx-hook="Flash"
        data-kind={kind}
        data-message={message}
      >
        <p class="min-w-0 flex-1 break-words">{message}</p>
        <button
          type="button"
          aria-label={gettext("Dismiss notification")}
          title={gettext("Dismiss notification")}
          class="shrink-0 rounded px-2 text-xl leading-6 text-slate-300 hover:bg-slate-700 hover:text-white focus-visible:outline focus-visible:outline-2 focus-visible:outline-teal-400"
          phx-click={JS.push("lv:clear-flash", value: %{key: kind})}
        >
          <span aria-hidden="true">×</span>
        </button>
      </div>
    </div>
    """
  end
end
