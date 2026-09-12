defmodule TijaraTidesWeb.GameSessionController do
  use TijaraTidesWeb, :controller
  alias TijaraTides.UseCases.Game

  def create(conn, %{"code" => code}) do
    # The browser must already hold this signed cookie from GET /play.
    # Minting a credential on POST would recreate the lost-response window.
    device_token = get_session(conn, :redemption_token)

    result =
      if is_binary(device_token) and byte_size(device_token) == 43,
        do: Game.redeem_for_device(code, device_token),
        else: {:error, :missing_device}

    case result do
      {:ok, %{"session" => token}} ->
        conn
        |> configure_session(renew: true)
        |> put_session(:account_token, token)
        |> delete_session(:redemption_token)
        |> redirect(to: ~p"/play")

      {:error, :missing_device} ->
        conn
        |> put_flash(:error, "Open the invitation form again and allow cookies before redeeming.")
        |> redirect(to: ~p"/play")

      {:error, _} ->
        conn
        |> put_flash(
          :error,
          "That invitation could not be redeemed. Check the code and that the game is available."
        )
        |> redirect(to: ~p"/play")
    end
  end

  def create(conn, _), do: redirect(conn, to: ~p"/play")

  def delete(conn, _) do
    Game.sign_out(get_session(conn, :account_token))

    conn
    |> delete_session(:account_token)
    |> delete_session(:redemption_token)
    |> configure_session(renew: true)
    |> redirect(to: ~p"/play")
  end
end
