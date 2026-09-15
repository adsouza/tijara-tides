defmodule TijaraTides.Domain.EmailIdentity do
  @moduledoc "Compatibility facade for Account email credentials."
  defdelegate delivered(state, row), to: TijaraTides.Domain.AccountWorld.EmailIdentity

  defdelegate delivery_failed(state, row, wall_ms),
    to: TijaraTides.Domain.AccountWorld.EmailIdentity

  defdelegate normalize(value), to: TijaraTides.Domain.AccountWorld.EmailIdentity

  defdelegate request(state, account, purpose, address, context),
    to: TijaraTides.Domain.AccountWorld.EmailIdentity

  defdelegate redeem(state, hash, session, signed_in, context),
    to: TijaraTides.Domain.AccountWorld.EmailIdentity
end
