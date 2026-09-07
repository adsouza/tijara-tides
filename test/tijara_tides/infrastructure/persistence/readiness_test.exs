defmodule TijaraTides.Infrastructure.Persistence.ReadinessTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Infrastructure.Persistence.Readiness

  test "answers during startup and caches success without repeating queries" do
    parent = self()

    check = fn ->
      send(parent, {:checking, self()})

      receive do
        :finish -> :ok
      end
    end

    server = start_supervised!({Readiness, name: nil, enabled: true, check: check})
    assert_receive {:checking, worker}
    assert Readiness.status(server) == :checking
    send(server, :unexpected)
    send(server, {make_ref(), :ready})
    assert Readiness.status(server) == :checking
    send(worker, :finish)
    await_status(server, :ready)
    send(server, :unexpected)
    send(server, {nil, :unexpected})
    send(server, {:DOWN, make_ref(), :process, worker, :normal})
    for _ <- 1..20, do: assert(Readiness.status(server) == :ready)
    refute_receive {:checking, _}
  end

  test "query errors and exceptions leave readiness failed" do
    for check <- [fn -> :error end, fn -> raise "private connection details" end] do
      server = start_supervised!({Readiness, name: nil, enabled: true, check: check})
      await_status(server, :failed)
      stop_supervised!(Readiness)
    end
  end

  test "missing configuration does not query and is not ready" do
    server =
      start_supervised!({Readiness, name: nil, enabled: false, check: fn -> flunk("queried") end})

    assert Readiness.status(server) == :not_configured
    send(server, {nil, :ready})
    send(server, :unexpected)
    assert Readiness.status(server) == :not_configured
  end

  test "missing readiness process is unavailable" do
    assert Readiness.status(:missing_readiness_process) == :unavailable
  end

  defp await_status(server, expected, attempts \\ 100)
  defp await_status(server, expected, 0), do: assert(Readiness.status(server) == expected)

  defp await_status(server, expected, attempts) do
    if Readiness.status(server) != expected do
      Process.sleep(10)
      await_status(server, expected, attempts - 1)
    end
  end
end
