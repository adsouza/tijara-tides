defmodule TijaraTidesWeb.MusicCreditsControllerTest do
  use TijaraTidesWeb.ConnCase, async: true
  import Phoenix.LiveViewTest, only: [render_component: 2]

  defp escape(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  # The rendered <article> for one track, so each assertion is about that track.
  defp article(html, slug) do
    [_, rest] = String.split(html, ~s(id="music-credit-#{slug}"), parts: 2)
    rest |> String.split("</article>", parts: 2) |> hd()
  end

  defp attribution(track) do
    [
      escape(track.title),
      escape(track.credit),
      escape(track.edits),
      ~s(href="#{escape(track.source_url)}" rel="noopener noreferrer">#{escape(track.source_url)}</a>),
      ~s(href="#{escape(track.licence_url)}" rel="noopener noreferrer">#{escape(track.licence)}</a>)
    ] ++
      for notice <- track.notices, do: ~s(href="#{escape(notice.url)}">#{escape(notice.name)}</a>)
  end

  test "lists every track's title, creators, source, licence and edits", %{conn: conn} do
    html = conn |> get("/music/credits") |> html_response(200)
    {:ok, manifest} = TijaraTidesWeb.Music.manifest()
    tracks = TijaraTidesWeb.Music.credits(manifest)
    assert length(tracks) == map_size(manifest["tracks"])

    for track <- tracks do
      assert track.licence_url == manifest["tracks"][track.slug]["licence_url"]
      section = article(html, track.slug)
      for expected <- attribution(track), do: assert(section =~ expected)
    end

    assert html =~ "Music credits"
  end

  test "links a track's licence and supplied notices with escaped text" do
    track = %{
      slug: "sea",
      palette: "East",
      role: "port",
      title: ~s(Sea & "Sky" <Tide>),
      credit: "O'Brien & Co",
      source_url: "https://example.test/sea?a=1&b=2",
      licence: ~s(Licence "A" & B),
      licence_url: "https://example.test/licence?x=1&y='2'",
      edits: "gain -1.00 dB; encoded as Opus 64 kbps.",
      notices: [%{name: ~s(Release & "Notice"), url: "/audio/notices/sea&release.pdf"}]
    }

    html = render_component(&TijaraTidesWeb.MusicCreditsHTML.show/1, tracks: [track])
    section = article(html, "sea")
    for expected <- attribution(track), do: assert(section =~ expected)
    refute html =~ ~s(Sea & "Sky")
  end
end
