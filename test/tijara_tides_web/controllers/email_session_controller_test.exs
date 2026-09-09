defmodule TijaraTidesWeb.EmailSessionControllerTest do
  use TijaraTidesWeb.ConnCase, async: false

  setup do
    previous = Application.get_env(:tijara_tides, :game_server)
    enabled = Application.get_env(:tijara_tides, :email_enabled)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:tijara_tides, :game_server, previous),
        else: Application.delete_env(:tijara_tides, :game_server)

      Application.put_env(:tijara_tides, :email_enabled, enabled)
    end)

    :ok
  end

  defmodule ReplyServer do
    use GenServer
    def start_link(args), do: GenServer.start_link(__MODULE__, args)
    def init(args), do: {:ok, args}

    def handle_call(request, _from, {owner, reply} = state) do
      send(owner, {:email_call, request})
      {:reply, reply, state}
    end
  end

  defp reply_with(reply) do
    server = start_supervised!({ReplyServer, {self(), reply}})
    Application.put_env(:tijara_tides, :game_server, server)
  end

  test "confirmation renders a protected POST form without exposing the bearer token", %{
    conn: conn
  } do
    token = String.duplicate("a", 43)
    prepared = get(conn, "/email/verify", token: token)
    page = prepared |> recycle() |> get("/email/confirm")
    html = html_response(page, 200)
    assert html =~ ~s(method="post" action="/email/redeem")
    assert html =~ ~s(name="_csrf_token" value=")
    refute html =~ token
    assert get_resp_header(page, "cache-control") == ["no-store"]
    assert get_resp_header(page, "referrer-policy") == ["no-referrer"]
    refute_received {:email_call, _}
  end

  test "malformed requests and links redirect without calling the world", %{conn: conn} do
    reply_with({:error, :unexpected})

    for params <- [%{}, %{"token" => "short"}] do
      assert conn |> get("/email/verify", params) |> redirected_to() == "/play"
    end

    assert conn |> post("/email/request", %{}) |> redirected_to() == "/play"
    refute_received {:email_call, _}
  end

  test "disabled delivery does not queue mail or reveal whether an account exists", %{conn: conn} do
    reply_with({:error, :unexpected})
    Application.put_env(:tijara_tides, :email_enabled, false)
    result = post(conn, "/email/request", email: "player@example.com", request_id: "request")
    assert redirected_to(result) == "/play"
    assert Phoenix.Flash.get(result.assigns.flash, :info) =~ "If that email is linked"
    refute_received {:email_call, _}
  end

  test "throttled requests keep the generic response", %{conn: conn} do
    reply_with({:error, :email_rate_limited})
    Application.put_env(:tijara_tides, :email_enabled, true)
    result = post(conn, "/email/request", email: "player@example.com", request_id: "request")
    assert Phoenix.Flash.get(result.assigns.flash, :info) =~ "If that email is linked"

    assert_receive {:email_call,
                    {:email_request, nil, "login", "player@example.com", "request", _}}
  end

  test "wrong-account redemption preserves the current account and pending link", %{conn: conn} do
    reply_with({:error, :email_wrong_account})

    result =
      conn
      |> init_test_session(
        account_token: "current",
        email_token: "pending",
        email_device: "device"
      )
      |> post("/email/redeem")

    assert Phoenix.Flash.get(result.assigns.flash, :error) =~ "Sign out before using it"
    assert get_session(result, :account_token) == "current"
    assert get_session(result, :email_token) == "pending"
    assert get_session(result, :email_device) == "device"
    assert get_resp_header(result, "cache-control") == ["no-store"]
    assert_receive {:email_call, {:email_redeem, "pending", "device", "current"}}
  end

  test "invalid redemption gives a recovery message without altering the session", %{conn: conn} do
    reply_with({:error, :email_link_invalid})
    result = conn |> init_test_session(account_token: "current") |> post("/email/redeem")
    assert redirected_to(result) == "/play"
    assert Phoenix.Flash.get(result.assigns.flash, :error) =~ "Request a new link"
    assert get_session(result, :account_token) == "current"
    assert get_resp_header(result, "referrer-policy") == ["no-referrer"]
  end

  test "reopening a link preserves the credential needed to recover a lost response", %{
    conn: conn
  } do
    token = String.duplicate("a", 43)
    first = get(conn, "/email/verify", token: token)
    device = get_session(first, :email_device)
    assert byte_size(device) == 43
    reopened = first |> recycle() |> get("/email/verify", token: token)
    assert get_session(reopened, :email_device) == device
    assert get_session(reopened, :email_token) == token
  end

  test "malformed device credentials are replaced", %{conn: conn} do
    conn =
      conn
      |> init_test_session(email_device: "short")
      |> get("/email/verify", token: String.duplicate("a", 43))

    assert byte_size(get_session(conn, :email_device)) == 43
  end

  test "request filtering includes secrets and email" do
    params = Map.new(~w(password secret token code email), &{&1, "private"})
    filtered = Phoenix.Logger.filter_values(params)
    assert Enum.all?(filtered, fn {_, value} -> value == "[FILTERED]" end)
  end

  test "pasted link signs in on this device only after confirmation", %{conn: conn} do
    token = String.duplicate("a", 43)
    reply_with({:ok, %{"session" => String.duplicate("s", 43)}})

    prepared =
      post(conn, "/email/open", email_link: "http://www.example.com/email/verify?token=#{token}")

    assert redirected_to(prepared) == "/email/confirm"
    assert get_session(prepared, :email_token) == token
    refute_received {:email_call, _}
    signed_in = prepared |> recycle() |> post("/email/redeem")
    assert get_session(signed_in, :account_token) == String.duplicate("s", 43)
    assert redirected_to(signed_in) == "/play"
  end

  test "pasted links reject other servers and malformed input", %{conn: conn} do
    for link <- [
          "https://evil.example/email/verify?token=" <> String.duplicate("a", 43),
          "javascript:alert(1)",
          "http://www.example.com/email/verify?token=short",
          "http://www.example.com/other?token=" <> String.duplicate("a", 43)
        ] do
      rejected = post(conn, "/email/open", email_link: link)
      assert redirected_to(rejected) == "/play"
      refute get_session(rejected, :email_token)
    end

    refute_received {:email_call, _}
  end

  test "raw email token prepares confirmation without redeeming", %{conn: conn} do
    token = String.duplicate("b", 43)
    prepared = post(conn, "/email/open", email_link: "  #{token}\n")
    assert redirected_to(prepared) == "/email/confirm"
    assert get_session(prepared, :email_token) == token
    refute get_session(prepared, :account_token)
    refute_received {:email_call, _}
  end
end
