defmodule TijaraTides.UseCases.WorldProjection do
  @moduledoc """
  Public read model for one committed world revision. Contains no accounts,
  sessions, receipts, cargo manifests or private accounting. Rebuilt after
  commit; never independently persisted or treated as authoritative write state.
  """
  alias TijaraTides.Domain.{ReadState, Visibility, Markets}
  @enforce_keys [:revision, :public, :markets]
  defstruct [:revision, :public, :markets]

  def build(game, catalogue) do
    %__MODULE__{
      revision: game.revision,
      public: Visibility.public(game, catalogue),
      markets:
        Map.new(ReadState.entities(game, "markets"), fn {id, market} ->
          {id, Markets.quote(game, catalogue, market["port"], market["good"])}
        end)
    }
  end
end
