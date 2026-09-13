defmodule TijaraTidesWeb.LocaleControllerTest do
  use TijaraTidesWeb.ConnCase, async: false

  defmodule UnavailableServer do
    use GenServer
    def start_link(_), do: GenServer.start_link(__MODULE__, nil)
    def init(_), do: {:ok, nil}

    def handle_call({:command, _, _, _}, _from, state),
      do: {:reply, {:error, :unavailable}, state}
  end

  test "English can be selected when the world cannot save preferences", %{conn: conn} do
    previous = Application.get_env(:tijara_tides, :game_server)
    server = start_supervised!(UnavailableServer)
    Application.put_env(:tijara_tides, :game_server, server)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:tijara_tides, :game_server, previous),
        else: Application.delete_env(:tijara_tides, :game_server)
    end)

    result =
      conn
      |> init_test_session(%{account_token: "account-session", locale: "ar"})
      |> post("/locale", locale: "en")

    assert redirected_to(result) == "/play"
    assert get_session(result, :locale) == "en"
    assert get_session(result, :locale_explicit)
    assert Phoenix.Flash.get(result.assigns.flash, :info) =~ "Language changed on this device"
  end

  test "anonymous preference survives requests and sets document direction", %{conn: conn} do
    result = post(conn, "/locale", locale: "ar")
    assert redirected_to(result) == "/play"
    assert get_session(result, :locale) == "ar"
    page = result |> recycle() |> get("/") |> html_response(200)
    assert page =~ ~s(lang="ar")
    assert page =~ ~s(dir="rtl")
    assert page =~ "العربية"
  end

  test "lobby language changes return to the lobby", %{conn: conn} do
    page = conn |> get("/") |> html_response(200)
    assert page =~ ~s(name="return_to" value="/")

    for locale <- ["ar", "en"] do
      result = conn |> recycle() |> post("/locale", locale: locale, return_to: "/")
      assert redirected_to(result) == "/"
      assert get_session(result, :locale) == locale
    end
  end

  test "game language changes stay in the game and arbitrary redirects are rejected", %{
    conn: conn
  } do
    for destination <- ["/play", "https://example.com", "//example.com", "/email/verify"] do
      result = conn |> recycle() |> post("/locale", locale: "en", return_to: destination)
      assert redirected_to(result) == "/play"
    end
  end

  test "unsupported preference is rejected", %{conn: conn} do
    assert conn |> post("/locale", locale: "unknown") |> response(400)
  end

  test "browser Arabic is used on the first request", %{conn: conn} do
    page =
      conn
      |> put_req_header("accept-language", "ar-EG, en;q=0.8")
      |> get("/")
      |> html_response(200)

    assert page =~ ~s(lang="ar")
  end
end
