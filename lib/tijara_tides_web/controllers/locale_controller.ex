defmodule TijaraTidesWeb.LocaleController do
  use TijaraTidesWeb, :controller
  alias TijaraTides.UseCases.Game

  def update(conn, %{"locale" => locale}) when locale in ["en", "ar"] do
    result =
      case get_session(conn, :account_token) do
        nil ->
          {:ok, %{}}

        token ->
          Game.command(token, Game.request_id(), %{"action" => "locale", "locale" => locale})
      end

    conn = conn |> put_session(:locale, locale) |> put_session(:locale_explicit, true)
    TijaraTides.Localization.put_locale(locale)

    conn =
      case result do
        {:ok, _} ->
          conn

        {:error, :invalid_session} ->
          conn

        _ ->
          put_flash(
            conn,
            :info,
            gettext(
              "Language changed on this device. Your account language could not be saved; try again when the world is available."
            )
          )
      end

    redirect(conn, to: "/play")
  end

  def update(conn, _), do: conn |> put_status(400) |> text("Unsupported language")
end
