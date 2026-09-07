defmodule TijaraTidesWeb.Plugs.RedemptionSession do
  @moduledoc "Deliver a private device credential before any invitation is consumed."
  import Plug.Conn
  alias TijaraTides.Infrastructure.GameServer

  def init(opts), do: opts

  def call(%{method: "GET", request_path: "/play"} = conn, _opts) do
    if get_session(conn, :account_token) do
      conn
    else
      case get_session(conn, :redemption_token) do
        token when is_binary(token) and byte_size(token) == 43 -> conn
        _ -> put_session(conn, :redemption_token, GameServer.token())
      end
    end
  end

  def call(conn, _opts), do: conn
end
