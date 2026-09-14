defmodule TijaraTides.UseCases.OperationsRuntime do
  @moduledoc "Readiness and diagnostic output without requiring gameplay or identity capabilities."
  @callback readiness() :: :ready | :unavailable | :not_configured
  @callback database_readiness() :: :ready | :unavailable | :not_configured | :checking | :failed
  @callback log_exception(String.t(), Exception.t(), Exception.stacktrace()) :: :ok
end
