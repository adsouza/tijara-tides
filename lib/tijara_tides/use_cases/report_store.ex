defmodule TijaraTides.UseCases.ReportStore do
  @moduledoc "Read-only reporting port. Returns bounded pages from one committed world revision."
  @callback page(term(), map(), String.t() | nil, map()) :: {:ok, map()} | {:error, term()}
end
