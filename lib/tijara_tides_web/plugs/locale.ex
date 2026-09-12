defmodule TijaraTidesWeb.Plugs.Locale do
  import Plug.Conn
  alias TijaraTides.Localization
  def init(opts), do: opts

  def call(conn, _) do
    locale =
      Localization.normalize(get_session(conn, :locale) || browser_locale(conn))

    Localization.put_locale(locale)
    conn |> put_session(:locale, locale) |> assign(:locale, locale)
  end

  defp browser_locale(conn) do
    supported = Enum.map(Localization.locales(), &elem(&1, 0))

    conn
    |> get_req_header("accept-language")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(fn entry ->
      [language | parameters] = entry |> String.downcase() |> String.split(";")
      language = language |> String.trim() |> String.split("-") |> hd()
      {language, quality(parameters)}
    end)
    # Stable sort preserves listed order for equally preferred languages.
    |> Enum.sort_by(fn {_, quality} -> -quality end)
    |> Enum.find_value("en", fn {language, quality} ->
      if quality > 0 and language in supported, do: language
    end)
  end

  defp quality(parameters) do
    case Enum.find_value(parameters, fn parameter ->
           case String.split(parameter, "=", parts: 2) do
             [key, value] -> if String.trim(key) == "q", do: String.trim(value)
             _ -> nil
           end
         end) do
      nil ->
        1.0

      value ->
        case Float.parse(value) do
          {number, ""} when number >= 0 and number <= 1 -> number
          _ -> 0.0
        end
    end
  end
end
