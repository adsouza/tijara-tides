defmodule TijaraTidesWeb.Plugs.ClientIpTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  alias TijaraTidesWeb.Plugs.ClientIp

  defp forwarded(peer, header) do
    %{Plug.Test.conn(:post, "/email/request") | remote_ip: peer}
    |> put_req_header("x-forwarded-for", header)
  end

  test "Render clients behind the same private and Cloudflare proxies resolve separately" do
    for {address, ip} <- [{"8.8.8.8", {8, 8, 8, 8}}, {"9.9.9.9", {9, 9, 9, 9}}] do
      conn = forwarded({10, 0, 0, 1}, address <> ", 172.64.1.2, 10.0.0.2")
      assert ClientIp.call(conn, enabled: true).remote_ip == ip
    end
  end

  test "spoofed leftmost addresses and unrelated headers do not override the client" do
    conn =
      forwarded({10, 0, 0, 1}, "1.1.1.1, 8.8.8.8, 172.64.1.2")
      |> put_req_header("x-real-ip", "2.2.2.2")
      |> put_req_header("forwarded", "for=3.3.3.3")

    assert ClientIp.call(conn, enabled: true).remote_ip == {8, 8, 8, 8}
    direct = %{conn | remote_ip: {9, 9, 9, 9}}
    assert ClientIp.call(direct, enabled: true).remote_ip == {9, 9, 9, 9}
    assert ClientIp.call(conn, enabled: false).remote_ip == {10, 0, 0, 1}
  end

  test "IPv6 and missing or invalid forwarding values" do
    conn = forwarded({10, 0, 0, 1}, "2001:4860:4860::8888, 2606:4700::1")
    {:ok, ip} = :inet.parse_address(~c"2001:4860:4860::8888")
    assert ClientIp.call(conn, enabled: true).remote_ip == ip

    for header <- ["", "garbage"] do
      conn = forwarded({10, 0, 0, 1}, header)
      assert ClientIp.call(conn, enabled: true).remote_ip == conn.remote_ip
    end
  end
end
