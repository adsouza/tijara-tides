defmodule TijaraTides.Domain.Accounts do
  @moduledoc "Compatibility facade; account lifecycle rules belong to Account."
  defdelegate sign_out(state, session_hash), to: TijaraTides.Domain.Account
  defdelegate authenticate(state, session_hash, wall_ms), to: TijaraTides.Domain.Account
  defdelegate seed_invite(state, hash), to: TijaraTides.Domain.Account
  defdelegate redeem(state, hash, session_hash, context), to: TijaraTides.Domain.Account

  defdelegate create_company(state, account, name, context),
    to: TijaraTides.Domain.Services.CompanyFormation

  defdelegate issue_invite(state, account, context), to: TijaraTides.Domain.Account
  defdelegate expire_invitations(state), to: TijaraTides.Domain.Account
end
