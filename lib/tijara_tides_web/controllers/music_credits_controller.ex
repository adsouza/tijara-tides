defmodule TijaraTidesWeb.MusicCreditsController do
  use TijaraTidesWeb, :controller
  alias TijaraTidesWeb.Music

  def show(conn, _params) do
    with {:ok, manifest} <- Music.manifest(),
         true <- Music.well_formed_manifest?(manifest) do
      render(conn, :show,
        page_title: gettext("Music credits"),
        tracks: Music.credits(manifest)
      )
    else
      _unavailable ->
        conn |> put_status(:not_found) |> text(gettext("Music credits are unavailable."))
    end
  end
end
