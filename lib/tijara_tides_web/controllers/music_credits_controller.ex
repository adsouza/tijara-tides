defmodule TijaraTidesWeb.MusicCreditsController do
  use TijaraTidesWeb, :controller

  def show(conn, _params) do
    case TijaraTidesWeb.Music.manifest() do
      {:ok, manifest} ->
        render(conn, :show,
          page_title: gettext("Music credits"),
          tracks: TijaraTidesWeb.Music.credits(manifest)
        )

      {:error, _reason} ->
        conn |> put_status(:not_found) |> text(gettext("Music credits are unavailable."))
    end
  end
end
