defmodule TijaraTides.Domain do
  @moduledoc "Pure game state and rules. No processes, transport, or persistence."
  use Boundary,
    type: :strict,
    deps: [],
    exports: [
      World,
      Game,
      Journal,
      Reporting,
      Account,
      Accounts,
      EmailIdentity,
      Commands,
      Ship,
      CompanyFinance,
      PortCargoMarket,
      Fleet,
      Trading,
      CargoRules,
      Markets,
      Visibility,
      ReadState
    ]
end
