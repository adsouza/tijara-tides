defmodule TijaraTides.Infrastructure.GameCallTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Infrastructure.GameServer

  test "missing credentials cannot be a session key" do
    assert GameServer.hash(nil) == nil
    refute is_binary(GameServer.hash(%{}))
  end

  test "reads and connection calls tolerate queued I/O beyond five seconds" do
    server =
      spawn_link(fn ->
        Process.sleep(5200)
        receive_calls(4)
      end)

    calls = [
      fn -> GameServer.snapshot(nil, server) end,
      fn -> GameServer.preview(nil, "ship", "port", server) end,
      fn -> GameServer.connect(nil, server) end,
      fn -> GameServer.sign_out(nil, server) end
    ]

    tasks = Enum.map(calls, &Task.async/1)
    assert Enum.map(tasks, &Task.await(&1, 10_000)) == [:ok, :ok, :ok, :ok]
  end

  defp receive_calls(0), do: :ok

  defp receive_calls(n) do
    receive do
      {:"$gen_call", from, _request} ->
        GenServer.reply(from, :ok)
        receive_calls(n - 1)
    end
  end
end
