defmodule TijaraTides.Infrastructure.GameReadiness do
  @moduledoc "Readiness without a call into the world owner's busy mailbox."
  @registry __MODULE__.Registry
  @max_age_ms 60_000

  def child_spec(_opts), do: Registry.child_spec(keys: :unique, name: @registry)

  def register(status) do
    case Registry.register(@registry, self(), {status, now()}) do
      {:ok, _} -> :ok
      {:error, {:already_registered, _}} -> publish(status)
    end
  end

  def publish(status) do
    Registry.update_value(@registry, self(), fn _ -> {status, now()} end)
    :ok
  end

  # The owner sends its own heartbeat even while the world is inactive. A long tick
  # may delay it, but an owner stalled for a full minute must fail readiness.
  def status(server, now_ms \\ now()) do
    with pid when is_pid(pid) <- GenServer.whereis(server),
         true <- Process.alive?(pid),
         [{^pid, {status, updated}}] <- Registry.lookup(@registry, pid),
         true <- now_ms - updated <= @max_age_ms do
      status
    else
      _ -> :unavailable
    end
  rescue
    ArgumentError -> :unavailable
  end

  defp now, do: System.monotonic_time(:millisecond)
end
