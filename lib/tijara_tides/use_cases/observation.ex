defmodule TijaraTides.UseCases.Observation do
  @moduledoc "Application observation port; the composition root supplies the telemetry adapter."
  @callback record(:conflict_retry | :conflict_exhausted | :conflict_reload_failed) :: :ok

  @callback measure(atom(), (-> term())) :: term()
  @callback command_exception(Exception.t(), Exception.stacktrace()) :: :ok
  @optional_callbacks measure: 2, command_exception: 2

  def command_exception(error, stacktrace) do
    adapter = Application.get_env(:tijara_tides, :observation_adapter)

    if adapter && Code.ensure_loaded?(adapter) &&
         function_exported?(adapter, :command_exception, 2),
       do: adapter.command_exception(error, stacktrace),
       else: :ok
  end

  def measure(phase, fun) do
    adapter = Application.get_env(:tijara_tides, :observation_adapter)

    if adapter && Code.ensure_loaded?(adapter) && function_exported?(adapter, :measure, 2),
      do: adapter.measure(phase, fun),
      else: fun.()
  end

  def record(event) do
    case Application.get_env(:tijara_tides, :observation_adapter) do
      nil -> :ok
      adapter -> adapter.record(event)
    end
  end
end
