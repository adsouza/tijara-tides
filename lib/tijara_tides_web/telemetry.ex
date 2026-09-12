defmodule TijaraTidesWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg), do: Supervisor.start_link(__MODULE__, arg, name: __MODULE__)

  @impl true
  def init(opts) do
    children = [
      {TelemetryMetricsPrometheus.Core,
       name: :tijara_metrics, metrics: metrics(), start_async: false},
      {:telemetry_poller,
       measurements: [{__MODULE__, :aggregate, []} | Keyword.get(opts, :measurements, [])],
       period: 5_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # The reporter buffers histogram observations until a scrape. Drain them even
  # when no external collector is configured, so samples cannot grow indefinitely.
  def aggregate do
    scrape()
    :ok
  end

  def scrape, do: TelemetryMetricsPrometheus.Core.scrape(:tijara_metrics)

  def metrics do
    database_event = [:tijara_tides, :infrastructure, :persistence, :repo, :query]

    [
      duration("tijara.operation.duration.seconds", [:tijara_tides, :operation, :stop], :duration,
        tags: [:operation, :outcome]
      ),
      counter("tijara.operation.total",
        event_name: [:tijara_tides, :operation, :stop],
        tags: [:operation, :outcome]
      ),
      counter("tijara.operation.exceptions.total",
        event_name: [:tijara_tides, :operation, :exception],
        tags: [:operation, :kind]
      ),
      duration("tijara.snapshot.build.seconds", [:tijara_tides, :snapshot], :duration),
      duration("tijara.snapshot.reply.seconds", [:tijara_tides, :snapshot], :reply),
      last_value("tijara.owner.mailbox.depth",
        event_name: [:tijara_tides, :owner],
        measurement: :mailbox_depth
      ),
      distribution("tijara.tick.lag.seconds",
        event_name: [:tijara_tides, :tick],
        measurement: :lag,
        unit: {:millisecond, :second},
        reporter_options: [buckets: [0.001, 0.01, 0.1, 0.5, 1, 5, 30]]
      ),
      sum("tijara.conflicts.total",
        event_name: [:tijara_tides, :conflict],
        measurement: :count,
        tags: [:outcome]
      ),
      duration("phoenix.http.duration.seconds", [:phoenix, :router_dispatch, :stop], :duration,
        tags: [:route]
      ),
      duration("phoenix.socket.connected.seconds", [:phoenix, :socket_connected], :duration),
      duration("phoenix.channel.joined.seconds", [:phoenix, :channel_joined], :duration),
      duration("phoenix.channel.handled.seconds", [:phoenix, :channel_handled_in], :duration,
        tags: [:event]
      ),
      sum("phoenix.socket.drain.total",
        event_name: [:phoenix, :socket_drain],
        measurement: :count
      ),
      last_value("vm.memory.total.bytes", event_name: [:vm, :memory], measurement: :total),
      last_value("vm.run.queue.total",
        event_name: [:vm, :total_run_queue_lengths],
        measurement: :total
      )
    ] ++
      for measurement <- [:query_time, :queue_time, :decode_time, :total_time] do
        duration("tijara.database.#{measurement}.seconds", database_event, measurement)
      end
  end

  defp duration(name, event, measurement, opts \\ []) do
    distribution(
      name,
      [
        event_name: event,
        measurement: measurement,
        unit: {:native, :second},
        reporter_options: [buckets: [0.0001, 0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1, 5, 30]]
      ] ++ opts
    )
  end
end
