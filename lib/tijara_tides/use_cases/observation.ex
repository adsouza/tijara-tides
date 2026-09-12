defmodule TijaraTides.UseCases.Observation do
  @moduledoc "Application observation port; the composition root supplies the telemetry adapter."
  @callback record(:conflict_retry | :conflict_exhausted | :conflict_reload_failed) :: :ok

  def record(event) do
    case Application.get_env(:tijara_tides, :observation_adapter) do
      nil -> :ok
      adapter -> adapter.record(event)
    end
  end
end
