defmodule TijaraTidesWeb.EmailSessionController do
  use TijaraTidesWeb, :controller
  alias TijaraTides.Infrastructure.GameServer

  def request(conn, %{"email" => email, "request_id" => request_id}) do
    if Application.get_env(:tijara_tides, :email_enabled, false) do
      GameServer.email_request(
        nil,
        "login",
        email,
        request_id,
        :inet.ntoa(conn.remote_ip) |> to_string()
      )
    end

    conn
    |> put_flash(
      :info,
      "If that email is linked to an account, a sign-in link will arrive shortly."
    )
    |> redirect(to: ~p"/play")
  end

  def request(conn, _), do: redirect(conn, to: ~p"/play")

  # GET does not consume the token: email scanners cannot redeem invitations.
  def prepare(conn, %{"token" => token}) when is_binary(token) and byte_size(token) == 43 do
    device =
      case get_session(conn, :email_device) do
        existing when is_binary(existing) and byte_size(existing) == 43 -> existing
        _ -> GameServer.token()
      end

    conn
    |> private_response()
    |> put_session(:email_token, token)
    |> put_session(:email_device, device)
    |> redirect(to: ~p"/email/confirm")
  end

  def prepare(conn, _), do: redirect(conn, to: ~p"/play")

  def confirm(conn, _) do
    csrf =
      Plug.CSRFProtection.get_csrf_token()
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()

    conn
    |> private_response()
    |> html("""
    <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"><title>Verify email · Tijara Tides</title>
    <style>body{margin:0;background:#0f172a;color:#e2e8f0;font:1rem/1.6 system-ui}main{max-width:32rem;margin:10vh auto;padding:2rem}h1{font-size:1.6rem}button{background:#5eead4;color:#0f172a;border:0;border-radius:.4rem;padding:.8rem 1rem;font:inherit;cursor:pointer}</style></head>
    <body><main><h1>Continue to Tijara Tides</h1><p>Confirm to verify this email and sign in. Only continue if you requested this link or were expecting this invitation.</p>
    <form method="post" action="/email/redeem"><input type="hidden" name="_csrf_token" value="#{csrf}"><button type="submit">Verify email and continue</button></form></main></body></html>
    """)
  end

  def redeem(conn, _) do
    result =
      GameServer.email_redeem(
        get_session(conn, :email_token),
        get_session(conn, :email_device),
        get_session(conn, :account_token)
      )

    case result do
      {:ok, %{"session" => token}} ->
        conn
        |> private_response()
        |> configure_session(renew: true)
        |> put_session(:account_token, token)
        |> delete_session(:email_token)
        |> delete_session(:email_device)
        |> delete_session(:redemption_token)
        |> put_flash(:info, "Email verified. You are signed in.")
        |> redirect(to: ~p"/play")

      {:error, :email_wrong_account} ->
        conn
        |> private_response()
        |> put_flash(
          :error,
          "This link belongs to a different account. Sign out before using it; accounts will not be merged."
        )
        |> redirect(to: ~p"/play")

      _ ->
        conn
        |> private_response()
        |> put_flash(
          :error,
          "This email link is invalid, expired, or already used. Request a new link."
        )
        |> redirect(to: ~p"/play")
    end
  end

  defp private_response(conn),
    do:
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("referrer-policy", "no-referrer")
end
