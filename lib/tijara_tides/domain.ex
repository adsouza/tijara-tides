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
      Accounts,
      EmailIdentity,
      Commands,
      Ship,
      Fleet,
      Trading,
      CargoRules,
      Markets,
      Visibility,
      ReadState
    ]
end
