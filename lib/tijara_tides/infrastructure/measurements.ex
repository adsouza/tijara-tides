defmodule TijaraTides.Infrastructure.Measurements do
  @moduledoc "Low-cardinality operational measurements without world reads or database probes."
  @behaviour TijaraTides.UseCases.Observation

  require Logger

  @impl true
  def measure(phase, fun) do
    started = System.monotonic_time()

    try do
      fun.()
    after
      duration = System.monotonic_time() - started
      operation = Keyword.get(Logger.metadata(), :operation, :unknown)

      :telemetry.execute([:tijara_tides, :phase, :stop], %{duration: duration}, %{
        phase: phase,
        operation: operation
      })

      milliseconds = System.convert_time_unit(duration, :native, :microsecond) / 1000

      if milliseconds >= 250 do
        Logger.info("operation=#{operation} phase=#{phase} duration_ms=#{milliseconds}")
      end
    end
  end

  @impl true
  def record(event) do
    outcome =
      case event do
        :conflict_retry -> :retry
        :conflict_exhausted -> :exhausted
        :conflict_reload_failed -> :reload_failed
      end

    :telemetry.execute([:tijara_tides, :conflict], %{count: 1}, %{outcome: outcome})
  end

  def poll_owner do
    server =
      Application.get_env(:tijara_tides, :game_server, TijaraTides.Infrastructure.GameServer)

    pid = if is_pid(server), do: server, else: Process.whereis(server)

    depth =
      case pid && Process.info(pid, :message_queue_len) do
        {:message_queue_len, depth} -> depth
        _ -> 0
      end

    :telemetry.execute([:tijara_tides, :owner], %{mailbox_depth: depth}, %{})
  end

  def tick_lag(due_ms, now_ms) when is_integer(due_ms) do
    :telemetry.execute([:tijara_tides, :tick], %{lag: max(0, now_ms - due_ms)}, %{})
  end

  def tick_lag(nil, _now), do: :ok
end
