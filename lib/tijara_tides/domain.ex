defmodule TijaraTides.Domain do
  @moduledoc "Pure game state and rules. No processes, transport, or persistence."
  use Boundary,
    type: :strict,
    deps: [],
    exports: [
      ChangeSet,
      EntityIndex,
      Game,
      Journal,
      Reporting,
      Account,
      Accounts,
      EmailIdentity,
      Commands,
      Ship,
      CompanyFinance,
      Services.FinancialSettlement,
      Services.Bankruptcy,
      Services.Credit,
      PortCargoMarket,
      Fleet,
      Trading,
      CargoRules,
      Markets,
      Visibility,
      ReadState
    ]
end
