defmodule TijaraTidesWeb.Plugs.ClientIp do
  @moduledoc "Resolve Render's forwarding chain, walking from the socket peer toward the client."
  import Plug.Conn

  # Render uses Cloudflare before its internal load balancers. Reviewed 2026-09-09:
  # https://www.cloudflare.com/ips-v4/ and https://www.cloudflare.com/ips-v6/
  @cloudflare ~w(173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22
    141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 188.114.96.0/20
    197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13
    104.24.0.0/14 172.64.0.0/13 131.0.72.0/22 2400:cb00::/32
    2606:4700::/32 2803:f800::/32 2405:b500::/32 2405:8100::/32
    2a06:98c0::/29 2c0f:f248::/32)

  def init(opts), do: opts

  def call(conn, opts) do
    enabled =
      Keyword.get(opts, :enabled, Application.get_env(:tijara_tides, :render_proxy, false))

    if enabled do
      # RemoteIp.from operates on headers alone. Include the socket peer so a
      # direct, untrusted connection cannot spoof its IP via forwarding headers.
      chain = get_req_header(conn, "x-forwarded-for") ++ [to_string(:inet.ntoa(conn.remote_ip))]

      ip =
        RemoteIp.from([{"x-forwarded-for", Enum.join(chain, ",")}],
          headers: ["x-forwarded-for"],
          proxies: @cloudflare
        )

      %{conn | remote_ip: ip || conn.remote_ip}
    else
      conn
    end
  end
end
