defmodule TijaraTides.Infrastructure do
  @moduledoc "OTP ownership and transport adapters."
  use Boundary,
    deps: [
      TijaraTides.Domain,
      TijaraTides.UseCases,
      Phoenix.PubSub,
      Ecto,
      Ecto.Repo,
      Ecto.Adapters.Postgres,
      Ecto.Adapters.SQL
    ],
    exports: [
      ExceptionLog,
      OperationLogger,
      GameServer,
      Mailer,
      EmailDelivery,
      GameQueries,
      GameCatalogue,
      Persistence.GameStore,
      Persistence.SchemaMaintenance,
      WorldServer,
      Persistence.Repo,
      Persistence.DatabaseConfig,
      Persistence.Readiness
    ]
end
