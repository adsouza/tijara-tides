defmodule TijaraTides.UseCases.CommandStore do
  @moduledoc "Application persistence port. One commit atomically stores state, accounting and receipt."
  @callback receipt(term(), String.t(), String.t(), String.t()) ::
              :new | {:replay, map()} | {:error, term()}
  @callback commit(term(), map(), map(), tuple()) :: {:ok, :ok} | {:error, term()}
end
