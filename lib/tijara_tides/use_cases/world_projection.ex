defmodule TijaraTides.UseCases.WorldProjection do
  @moduledoc """
  Public read model for one committed world revision. Contains no accounts,
  sessions, receipts, cargo manifests or private accounting. Rebuilt after
  commit; never independently persisted or treated as authoritative write state.
  """
  alias TijaraTides.Domain.{Visibility, Markets}
  @enforce_keys [:revision, :public, :markets]
  defstruct [:revision, :public, :markets]

  def build(game, catalogue) do
    %__MODULE__{
      revision: game.revision,
      public: Visibility.public(game, catalogue),
      markets: Markets.quotes(game, catalogue)
    }
  end
end
