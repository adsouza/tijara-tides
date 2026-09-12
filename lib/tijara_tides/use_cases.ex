defmodule TijaraTides.UseCases do
  @moduledoc "Transport-independent application operations."
  use Boundary,
    deps: [TijaraTides.Domain],
    exports: [
      Game,
      LotAllocation,
      GameRuntime,
      CommitExecutor,
      LifecycleCommands,
      CommitPreparation,
      ReportQueries,
      ReportStore,
      GameCommands,
      CommandStore,
      CommandRequest,
      CommandResult,
      GameQueries,
      WorldProjection
    ]
end
