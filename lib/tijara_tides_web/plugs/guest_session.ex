defmodule TijaraTidesWeb.Plugs.GuestSession do
  @moduledoc "Server-minted guest identity in the signed session; not an account."
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :player_id) do
      id when is_binary(id) and byte_size(id) == 43 ->
        conn

      _ ->
        put_session(
          conn,
          :player_id,
          Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
        )
    end
  end
end
