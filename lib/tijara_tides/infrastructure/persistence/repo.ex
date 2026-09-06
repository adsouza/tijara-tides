defmodule TijaraTides.Infrastructure.Persistence.Repo do
  @moduledoc "PostgreSQL adapter. Gameplay schemas and persistence operations are not implemented yet."
  use Ecto.Repo, otp_app: :tijara_tides, adapter: Ecto.Adapters.Postgres
end
