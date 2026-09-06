defmodule TijaraTides.Infrastructure.Persistence.Readiness do
  @moduledoc "Caches one database connectivity check per supervised startup; never polls Neon."
  use GenServer
  require Logger

  alias TijaraTides.Infrastructure.Persistence.Repo

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def status(server \\ __MODULE__) do
    GenServer.call(server, :status)
  catch
    :exit, _ -> :unavailable
  end

  @impl true
  def init(opts) do
    enabled = Keyword.get(opts, :enabled, Application.get_env(:tijara_tides, :start_repo, false))

    if enabled do
      check = Keyword.get(opts, :check, &check_database/0)
      {:ok, %{status: :checking, task: nil}, {:continue, {:check, check}}}
    else
      {:ok, %{status: :not_configured, task: nil}}
    end
  end

  @impl true
  def handle_continue({:check, check}, state) do
    task = Task.async(fn -> safely_check(check) end)
    {:noreply, %{state | task: task.ref}}
  end

  @impl true
  def handle_call(:status, _from, state), do: {:reply, state.status, state}

  @impl true
  def handle_info({ref, result}, %{task: ref} = state) do
    Process.demonitor(ref, [:flush])

    case result do
      :ready ->
        Logger.info("Startup database connectivity check passed")

      :failed ->
        Logger.error("Startup database connectivity check failed; readiness remains unavailable")
    end

    {:noreply, %{state | status: result, task: nil}}
  end

  defp safely_check(check) do
    case check.() do
      :ok -> :ready
      _ -> :failed
    end
  rescue
    _ -> :failed
  catch
    _, _ -> :failed
  end

  defp check_database do
    case Repo.query("SELECT 1", [], timeout: 30_000, log: false) do
      {:ok, %{rows: [[1]]}} -> :ok
      _ -> :error
    end
  end
end
