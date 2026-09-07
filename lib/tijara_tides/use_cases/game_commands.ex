defmodule TijaraTides.UseCases.GameCommands do
  @moduledoc "Authenticated game command dispatch, independent of transport and storage."
  defdelegate execute(state, account, command, context, catalogue), to: TijaraTides.Domain.Game
end
