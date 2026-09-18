defmodule TijaraTides.Infrastructure.GameReadiness do
  @moduledoc "Readiness without a call into the world owner's busy mailbox."
  require Logger
  @registry __MODULE__.Registry
  @max_age_ms 60_000

  def child_spec(_opts), do: Registry.child_spec(keys: :unique, name: @registry)

  def register(status) do
    case Registry.register(@registry, self(), {status, now()}) do
      {:ok, _} -> :ok
      {:error, {:already_registered, _}} -> publish(status)
    end
  end

  # Only the registered owner may publish. A caller that holds no entry would
  # otherwise leave a stale status standing while believing it had replaced it.
  def publish(status) do
    case Registry.update_value(@registry, self(), fn _ -> {status, now()} end) do
      :error ->
        Logger.error("Readiness #{inspect(status)} dropped: #{inspect(self())} owns no entry")
        :error

      _ ->
        :ok
    end
  end

  # The owner sends its own heartbeat even while the world is inactive. A long tick
  # may delay it, but an owner stalled for a full minute must fail readiness. An
  # owner still inside init/1 cannot beat at all, so :starting never goes stale.
  def status(server, now_ms \\ now()) do
    with pid when is_pid(pid) <- GenServer.whereis(server),
         true <- Process.alive?(pid),
         [{^pid, {status, updated}}] <- Registry.lookup(@registry, pid),
         true <- status == :starting or now_ms - updated <= @max_age_ms do
      status
    else
      _ -> :unavailable
    end
  rescue
    ArgumentError -> :unavailable
  end

  defp now, do: System.monotonic_time(:millisecond)
end
