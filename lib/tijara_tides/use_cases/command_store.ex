defmodule TijaraTides.UseCases.CommandStore do
  @moduledoc "Application persistence port. One commit atomically stores state, accounting and receipt."
  @callback receipt(term(), String.t(), String.t(), String.t()) ::
              :new | {:replay, map()} | {:error, term()}
  @callback commit(term(), map(), map(), tuple() | nil) :: {:ok, :ok} | {:error, term()}
  @callback restore(term(), map(), term()) :: map()
  @optional_callbacks restore: 3
end
