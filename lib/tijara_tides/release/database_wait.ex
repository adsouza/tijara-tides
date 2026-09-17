defmodule TijaraTides.Release.DatabaseWait do
  @moduledoc "Bounded connection preflight; never retries schema or migration operations."
  require Logger

  def await(repo, opts \\ []) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    sleep = Keyword.get(opts, :sleep, &Process.sleep/1)
    budget = Keyword.get(opts, :timeout, 60_000)

    check =
      Keyword.get(opts, :check, fn timeout ->
        Ecto.Adapters.SQL.query(repo, "SELECT 1", [], timeout: timeout, log: false)
      end)

    poll(check, clock, sleep, clock.() + budget)
  end

  defp poll(check, clock, sleep, deadline) do
    remaining = deadline - clock.()
    if remaining <= 0, do: unavailable!()

    case probe(check, min(5000, remaining)) do
      {:ok, %{rows: [[1]]}} ->
        :ok

      {:error, %DBConnection.ConnectionError{}} ->
        remaining = deadline - clock.()
        if remaining <= 0, do: unavailable!()

        Logger.warning(
          "Waiting for database connectivity before migrations; retrying within startup deadline"
        )

        sleep.(min(1000, remaining))
        poll(check, clock, sleep, deadline)

      {:error, error} ->
        raise error
    end
  end

  defp probe(check, timeout) do
    check.(timeout)
  rescue
    error in DBConnection.ConnectionError -> {:error, error}
  end

  defp unavailable!,
    do:
      raise(
        "Database connectivity was not ready within the migration startup deadline; no migrations attempted"
      )
end
