defmodule TijaraTides.UseCases.GameRuntime do
  @moduledoc "Runtime port for gameplay commands, authenticated reads and world subscriptions."
  @type session :: String.t() | nil
  @type result :: {:ok, map()} | {:error, term()}
  @callback snapshot(session()) :: map()
  @callback reports(session(), map()) :: result()
  @callback preview(session(), String.t(), String.t()) :: map() | nil | {:error, term()}
  @callback command(session(), String.t(), map()) :: result()
  @callback connect(session()) :: :ok | {:error, term()}
  @callback subscribe() :: :ok | {:error, term()}
  @callback definitions() :: map()
  @callback request_id() :: String.t()
end
