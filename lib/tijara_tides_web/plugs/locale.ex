defmodule TijaraTidesWeb.Plugs.Locale do
  import Plug.Conn
  alias TijaraTides.Localization
  def init(opts), do: opts

  def call(conn, _) do
    browser = get_req_header(conn, "accept-language") |> List.first() || "en"
    preferred = browser |> String.split([",", ";", "-"]) |> List.first()
    locale = Localization.normalize(get_session(conn, :locale) || preferred)
    Localization.put_locale(locale)
    conn |> put_session(:locale, locale) |> assign(:locale, locale)
  end
end
