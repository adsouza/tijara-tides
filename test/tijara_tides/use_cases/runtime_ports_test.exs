defmodule TijaraTides.UseCases.RuntimePortsTest do
  use ExUnit.Case, async: false
  alias TijaraTides.UseCases.Game

  # Deliberately narrow adapters: none implements another port's capabilities.
  defmodule Gameplay do
    def snapshot(token), do: %{session: token, status: :ready}
    def command(token, id, payload), do: {:ok, %{session: token, id: id, payload: payload}}
  end

  defmodule Identity do
    def token, do: "device-token"

    def email_redeem(code, device, session),
      do: {:ok, %{code: code, device: device, session: session}}
  end

  defmodule Presence do
    def presence_snapshot,
      do: %{world_id: "ocean", revision: 1, connections: 2, online_players: 1}

    def presence_detach, do: :ok
  end

  defmodule Operations do
    def readiness, do: :unavailable
    def database_readiness, do: :ready

    def log_exception(message, error, stack) do
      send(self(), {:diagnostic, message, error, stack})
      :ok
    end
  end

  setup do
    adapters = [
      game_runtime: Gameplay,
      identity_runtime: Identity,
      presence_runtime: Presence,
      operations_runtime: Operations
    ]

    previous =
      Enum.map(adapters, fn {key, _} -> {key, Application.fetch_env!(:tijara_tides, key)} end)

    for {key, adapter} <- adapters, do: Application.put_env(:tijara_tides, key, adapter)

    on_exit(fn ->
      for {key, adapter} <- previous, do: Application.put_env(:tijara_tides, key, adapter)
    end)

    :ok
  end

  test "narrow adapters serve independent consumers without a combined runtime" do
    assert Game.readiness() == :unavailable
    assert Game.database_readiness() == :ready
    assert Game.snapshot("session") == %{session: "session", status: :ready}

    assert Game.command("session", "request", %{"action" => "sail"}) ==
             {:ok, %{session: "session", id: "request", payload: %{"action" => "sail"}}}

    assert Game.token() == "device-token"

    assert Game.email_redeem("code", "device", "session") ==
             {:ok, %{code: "code", device: "device", session: "session"}}

    assert Game.presence_snapshot().connections == 2
    assert Game.presence_detach() == :ok
    error = RuntimeError.exception("failure")
    assert Game.log_exception("context", error, []) == :ok
    assert_received {:diagnostic, "context", ^error, []}
  end
end
