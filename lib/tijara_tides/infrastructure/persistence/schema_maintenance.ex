defmodule TijaraTides.Infrastructure.Persistence.SchemaMaintenance do
  @moduledoc "Serialize schema changes with world claims and fence existing writers before upgrades."
  @lock 8_417_229_301

  def with_lock(repo, fun) do
    repo.checkout(
      fn ->
        repo.query!("SELECT pg_advisory_lock($1)", [@lock], timeout: 60_000)

        try do
          fun.()
        after
          repo.query!("SELECT pg_advisory_unlock($1)", [@lock])
        end
      end,
      timeout: 120_000
    )
  end

  # Must be called inside the transaction that claims the world. Once claimed,
  # ordinary commits remain protected by the world's existing epoch check.
  def lock_claim(repo),
    do: repo.query!("SELECT pg_advisory_xact_lock($1)", [@lock], timeout: 60_000)

  def fence_writers(repo) do
    if repo.query!("SELECT to_regclass('game_worlds') IS NOT NULL", []).rows == [[true]] do
      repo.query!("UPDATE game_worlds SET epoch=epoch+1", [])
    end

    :ok
  end
end
