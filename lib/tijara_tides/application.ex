defmodule TijaraTides.Application do
  @moduledoc false
  use Application

  use Boundary,
    top_level?: true,
    deps: [TijaraTides.Infrastructure, TijaraTidesWeb, Phoenix.PubSub]

  @impl true
  def start(_type, _args) do
    children =
      repo_children() ++
        [
          TijaraTides.Infrastructure.Persistence.Readiness,
          TijaraTidesWeb.Telemetry,
          {Phoenix.PubSub, name: TijaraTides.PubSub},
          {TijaraTides.Infrastructure.WorldServer, name: TijaraTides.Infrastructure.WorldServer},
          TijaraTidesWeb.Endpoint
        ]

    # Losing PubSub or the world also reconnects clients to a fresh snapshot.
    Supervisor.start_link(children, strategy: :rest_for_one, name: TijaraTides.Supervisor)
  end

  defp repo_children do
    if Application.get_env(:tijara_tides, :start_repo, false) do
      [TijaraTides.Infrastructure.Persistence.Repo]
    else
      []
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    TijaraTidesWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
