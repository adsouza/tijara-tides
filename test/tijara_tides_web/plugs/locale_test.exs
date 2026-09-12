defmodule TijaraTidesWeb.Plugs.LocaleTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Plug.Test
  alias TijaraTidesWeb.Plugs.Locale

  test "chooses supported languages throughout the preference list" do
    for {header, expected} <- [
          {"fr-FR, ar-SA;q=0.9, en;q=0.8", "ar"},
          {"de, fr, en-GB, ar", "en"},
          {"FR, AR-eg", "ar"},
          {"fr;q=1, en;q=0.5, ar;q=0.9", "ar"},
          {"ar;q=0.8, en;q=0.8", "ar"},
          {"ar;q=0, en;q=0.5", "en"},
          {"ar;q=invalid, en", "en"},
          {"ar;q=2, en", "en"},
          {"*, ar", "ar"},
          {"fr, de", "en"},
          {"", "en"}
        ] do
      result =
        conn(:get, "/")
        |> put_req_header("accept-language", header)
        |> init_test_session(%{})
        |> Locale.call([])

      assert result.assigns.locale == expected, header
      assert get_session(result, :locale) == expected
    end
  end

  test "saved choices take precedence and missing headers default to English" do
    for {session, expected} <- [{%{}, "en"}, {%{locale: "ar"}, "ar"}] do
      result = conn(:get, "/") |> init_test_session(session) |> Locale.call([])
      assert result.assigns.locale == expected
    end

    result =
      conn(:get, "/")
      |> put_req_header("accept-language", "ar")
      |> init_test_session(%{locale: "en"})
      |> Locale.call([])

    assert result.assigns.locale == "en"
  end
end
