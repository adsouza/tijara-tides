defmodule TijaraTides.Infrastructure.OperationLogger do
  @moduledoc "Central logging policy for instrumented operations; successful operations log at debug."
  require Logger

  def attach do
    case :telemetry.attach_many(
           __MODULE__,
           [
             [:tijara_tides, :operation, :stop],
             [:tijara_tides, :operation, :exception]
           ],
           &__MODULE__.handle_event/4,
           nil
         ) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  def handle_event(_event, %{duration: duration}, metadata, _config) do
    milliseconds = System.convert_time_unit(duration, :native, :microsecond) / 1000

    level =
      cond do
        metadata.outcome in [:exception, :halted] or Map.has_key?(metadata, :diagnostic) -> :error
        metadata.outcome == :error -> :warning
        true -> :debug
      end

    Logger.log(level, fn ->
      "operation=#{metadata.operation} outcome=#{metadata.outcome} " <>
        "duration_ms=#{milliseconds} correlation_id=#{metadata.correlation_id}" <>
        if(Map.has_key?(metadata, :reason), do: " reason=#{metadata.reason}", else: "") <>
        if(Map.has_key?(metadata, :diagnostic), do: "\n#{metadata.diagnostic}", else: "")
    end)
  end
end
