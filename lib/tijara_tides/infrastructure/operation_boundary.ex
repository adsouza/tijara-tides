defmodule TijaraTides.Infrastructure.OperationBoundary do
  @moduledoc """
  Adapter failure policy. Operation logs exceptions once; this boundary classifies
  them and applies the caller's explicit recovery response. Exits and throws retain
  their OTP semantics. Domain errors and conflict retries remain ordinary results.
  """
  alias TijaraTides.Infrastructure.Operation

  def run(operation, fun, on_exception) do
    Operation.run(operation, fun)
  rescue
    error -> on_exception.(classify(error))
  end

  def classify(%Postgrex.Error{}), do: :storage_unavailable
  def classify(%DBConnection.ConnectionError{}), do: :storage_unavailable
  def classify(_), do: :internal_error

  def pause(state) do
    TijaraTides.Infrastructure.GameReadiness.publish(:unavailable)
    %{state | status: :unavailable, active: false}
  end

  def call(operation, state, execute, accept, refresh, decorate \\ &{:ok, &1}) do
    run(
      operation,
      fn -> reply(execute.(), state, accept, refresh, decorate) end,
      fn reason -> {:reply, {:error, reason}, pause(state)} end
    )
  end

  defp reply({:ok, outcome}, state, accept, _refresh, decorate),
    do: {:reply, decorate.(outcome.reply), accept.(state, outcome)}

  defp reply({:error, reason, fresh}, state, _accept, refresh, _decorate),
    do: {:reply, {:error, reason}, refresh.(state, fresh)}

  defp reply({:error, reason}, state, _accept, _refresh, _decorate),
    do: {:reply, {:error, reason}, state}

  defp reply({:halt, reason}, state, _accept, _refresh, _decorate),
    do: {:reply, {:error, reason}, pause(state)}
end
