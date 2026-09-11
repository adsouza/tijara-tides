defmodule TijaraTides.UseCases.CommandStore do
  @moduledoc "Application persistence port. One commit atomically stores state, accounting and receipt."
  @callback receipt(term(), String.t(), String.t(), String.t()) ::
              :new | {:replay, map()} | {:error, term()}
  @callback commit(term(), map(), map(), tuple() | nil) :: {:ok, :ok} | {:error, term()}
  @doc "Read durable identity history back into the cache before a retry. Returning `game` is a valid no-op."
  @callback restore(term(), map(), term()) :: map()
end
