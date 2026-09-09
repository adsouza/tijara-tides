defmodule TijaraTides.Domain.Game do
  @moduledoc "Compatibility facade. Rules belong to the focused domain modules."
  defdelegate classes(), to: TijaraTides.Domain.Fleet
  defdelegate entities(arg0, arg1), to: TijaraTides.Domain.ReadState
  defdelegate get(arg0, arg1, arg2), to: TijaraTides.Domain.ReadState
  defdelegate initialize(arg0, arg1), to: TijaraTides.Domain.Simulation
  defdelegate authenticate(arg0, arg1, arg2), to: TijaraTides.Domain.Accounts
  defdelegate execute(arg0, arg1, arg2, arg3, arg4), to: TijaraTides.Domain.Commands
  defdelegate seed_invite(arg0, arg1), to: TijaraTides.Domain.Accounts
  defdelegate redeem(arg0, arg1, arg2, arg3), to: TijaraTides.Domain.Accounts
  defdelegate quote(arg0, arg1, arg2, arg3), to: TijaraTides.Domain.Markets
  defdelegate capacity(arg0, arg1), to: TijaraTides.Domain.Fleet
  defdelegate compatible_cargo?(arg0, arg1), to: TijaraTides.Domain.CargoRules
  defdelegate purchase_total(arg0, arg1, arg2, arg3), to: TijaraTides.Domain.Trading

  defdelegate purchase_voyage(arg0, arg1, arg2, arg3, arg4, arg5, arg6),
    to: TijaraTides.Domain.Trading

  defdelegate handling_ms(arg0), to: TijaraTides.Domain.CargoRules
  defdelegate freshness(arg0, arg1, arg2, arg3), to: TijaraTides.Domain.CargoRules
  defdelegate voyage_freshness(arg0, arg1, arg2), to: TijaraTides.Domain.CargoRules
  defdelegate voyage_quote(arg0, arg1, arg2), to: TijaraTides.Domain.Fleet
  defdelegate raw_goods(), to: TijaraTides.Domain.Markets
  defdelegate advance(arg0, arg1, arg2), to: TijaraTides.Domain.Simulation
  defdelegate public(arg0, arg1), to: TijaraTides.Domain.Visibility
  defdelegate private(arg0, arg1), to: TijaraTides.Domain.Visibility
end
