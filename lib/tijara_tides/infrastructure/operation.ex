defmodule TijaraTides.Infrastructure.Operation do
  @moduledoc """
  Instruments adapter operations without changing their return or failure semantics.

  Events are `[:tijara_tides, :operation, :start | :stop | :exception]`.
  Durations use native monotonic units. Each invocation has a generated correlation
  ID, also scoped to Logger metadata. Arguments and results never enter events;
  exception diagnostics go through ExceptionLog's redaction policy.
  """
  alias TijaraTides.Infrastructure.ExceptionLog

  def run(operation, fun) when is_atom(operation) and is_function(fun, 0) do
    metadata = %{
      operation: operation,
      correlation_id: Base.encode16(:crypto.strong_rand_bytes(16))
    }

    previous = Logger.metadata()
    Logger.metadata(correlation_id: metadata.correlation_id)
    started = System.monotonic_time()

    try do
      emit(:start, %{system_time: System.system_time()}, metadata)
      result = fun.()

      emit(
        :stop,
        %{duration: System.monotonic_time() - started},
        Map.merge(metadata, outcome(result))
      )

      result
    catch
      kind, reason ->
        diagnostic =
          if kind == :error and is_exception(reason) do
            ExceptionLog.format("Operation failed", reason, __STACKTRACE__)
          else
            # Exit/throw payloads may include complete calls and credentials.
            "Operation failed: #{kind} (payload redacted)"
          end

        emit(
          :exception,
          %{duration: System.monotonic_time() - started},
          Map.merge(metadata, %{outcome: :exception, kind: kind, diagnostic: diagnostic})
        )

        :erlang.raise(kind, reason, __STACKTRACE__)
    after
      Logger.reset_metadata(previous)
    end
  end

  defp outcome({:reply, reply, %{status: :unavailable}}),
    do: Map.put(outcome(reply), :outcome, :halted)

  defp outcome({:reply, reply, _state}), do: outcome(reply)
  defp outcome({:noreply, %{status: :unavailable}}), do: %{outcome: :halted}
  defp outcome({:halt, reason}), do: %{outcome: :halted, reason: safe_reason(reason)}

  defp outcome({:error, reason}) when is_exception(reason),
    do: %{outcome: :error, diagnostic: ExceptionLog.format("Operation failed", reason, [])}

  defp outcome({:error, reason}), do: %{outcome: :error, reason: safe_reason(reason)}
  defp outcome({:ok, %{committed?: false}}), do: %{outcome: :replay}
  defp outcome(_result), do: %{outcome: :ok}

  defp safe_reason(reason) when is_atom(reason), do: reason
  defp safe_reason(_reason), do: :redacted

  defp emit(event, measurements, metadata),
    do: :telemetry.execute([:tijara_tides, :operation, event], measurements, metadata)
end
