defmodule TijaraTides.Infrastructure.Persistence.Repo do
  @moduledoc "PostgreSQL adapter for durable game entities, world ownership, and command receipts."
  use Ecto.Repo, otp_app: :tijara_tides, adapter: Ecto.Adapters.Postgres
end
