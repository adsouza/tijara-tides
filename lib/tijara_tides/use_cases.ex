defmodule TijaraTides.UseCases do
  @moduledoc "Transport-independent application operations."
  use Boundary,
    deps: [TijaraTides.Domain],
    exports: [
      Game,
      Observation,
      Authentication,
      LotAllocation,
      GameRuntime,
      IdentityRuntime,
      PresenceRuntime,
      OperationsRuntime,
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
