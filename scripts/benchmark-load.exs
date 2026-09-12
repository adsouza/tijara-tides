# Concurrent-client load harness for the world owner.
#
# Every snapshot, command and tick is serialized through one process, so this measures
# what the state benchmark cannot: how round-trip latency behaves as clients contend
# for that process, and how much of the owner's capacity real work actually consumes.
#
# Three things this deliberately does NOT claim:
#
#   * Round trip minus handler is not queueing delay. Round trip includes message
#     copying, scheduling and reply delivery, and the handler duration excludes
#     mailbox waiting entirely. Percentiles computed over different populations
#     cannot be subtracted. Mean wait is estimated separately, from Little's law.
#   * Mailbox depth is not a saturation signal. Each client holds one in-flight call,
#     so depth is bounded by the client count by construction.
#   * Logs are not a measurement channel. Under load the OTP handler enters drop mode
#     and discards a large fraction of messages, so telemetry is consumed directly.
#
# Run with scripts/benchmark-load.py, which supplies a disposable PostgreSQL.
alias TijaraTides.Infrastructure.GameServer
alias TijaraTides.Infrastructure.Persistence.Repo

readers = String.to_integer(System.get_env("LOAD_CLIENTS", "32"))
writers = String.to_integer(System.get_env("LOAD_WRITERS", "1"))
seconds = String.to_integer(System.get_env("LOAD_SECONDS", "10"))
tick_ms = String.to_integer(System.get_env("LOAD_TICK_MS", "5000"))

# Pacing. Workers that loop without pausing do not model players; they model a machine
# with no idle time, and on a host shared with PostgreSQL they oversubscribe the cores.
# A span measured there records waiting for a scheduler, not work. Zero keeps the old
# flat-out behaviour, which is a throughput ceiling rather than a workload.
think_ms = String.to_integer(System.get_env("LOAD_THINK_MS", "0"))
read_think_ms = String.to_integer(System.get_env("LOAD_READ_THINK_MS", "0"))
think = fn ms -> if ms > 0, do: Process.sleep(ms) end
port = System.fetch_env!("TIJARA_TEST_DB_PORT") |> String.to_integer()

# The harness runs in MIX_ENV=test for its database configuration, which also turns on
# the whole-world mutation audit. Production never pays that, so neither does this.
Application.put_env(:tijara_tides, :audit_mutations, false)

{:ok, _} =
  Repo.start_link(
    hostname: "127.0.0.1",
    port: port,
    username: "postgres",
    database: "postgres",
    ssl: false,
    pool_size: 16
  )

Ecto.Migrator.run(
  Repo,
  Application.app_dir(:tijara_tides, "priv/repo/migrations"),
  :up,
  all: true,
  log: false
)

world = Ecto.UUID.generate()

{:ok, server} =
  GameServer.start_link(name: nil, enabled: true, world_id: world, tick_ms: tick_ms)

companies = String.to_integer(System.get_env("LOAD_COMPANIES", "1"))
max_ships = String.to_integer(System.get_env("LOAD_SHIPS", "3"))

# Each player is an independent seed invitation: redeem, form a company, draw credit
# and buy hulls. Company formation is zero-asset, so an unseeded world would measure
# reads over empty private state and understate the owner's real work.
seed_started = System.monotonic_time(:millisecond)

tokens =
  for company <- 1..companies do
    {:ok, code} = GameServer.seed(server)
    {:ok, %{"session" => token}} = GameServer.redeem_for_device(code, GameServer.token(), server)
    send_command = fn id, payload -> GameServer.command(token, id, payload, server) end

    {:ok, _} =
      send_command.("company-#{company}", %{
        "action" => "company",
        "name" => "Load #{company}",
        "port" => "Jakarta",
        "package" => "general"
      })

    hulls = rem(company - 1, max_ships) + 1

    # Draw only what the hulls cost. Exhausting the credit limit here would make every
    # writer borrow fail with :loan_limit and silently measure no commits at all.
    {:ok, _} =
      send_command.("credit-#{company}", %{
        "action" => "borrow",
        "amount" => hulls * 4_100_000
      })

    for hull <- 1..hulls do
      {:ok, _} =
        send_command.("ship-#{company}-#{hull}", %{
          "action" => "purchase_ship",
          "class" => "freighter",
          "port" => "Jakarta",
          "price_limit" => 4_000_000
        })
    end

    token
  end

token = hd(tokens)
seed_ms = System.monotonic_time(:millisecond) - seed_started

:ok = GameServer.connect(token, server)

public = GameServer.snapshot(token, server).public
total_ships = map_size(public["ships"] || %{})

IO.puts("""
world #{String.slice(world, 0, 8)}: #{companies} companies, #{total_ships} ships \
(seeded in #{seed_ms}ms), audit_mutations off
#{readers} readers + #{writers} writers x #{seconds}s, tick #{tick_ms}ms
think #{think_ms}ms between commands, #{read_think_ms}ms between reads
""")

# Collect only the measured workload; company formation and hull purchases are setup.
table = :ets.new(:samples, [:public, :duplicate_bag])

:telemetry.attach_many(
  "load-harness",
  [[:tijara_tides, :operation, :stop], [:tijara_tides, :snapshot]],
  fn event, measurements, metadata, _config ->
    micro = &System.convert_time_unit(&1, :native, :microsecond)

    case event do
      # Two halves of one read: building the view, then flattening it into the caller.
      # The second is the larger, and is invisible to a span that ends with the callback.
      [:tijara_tides, :snapshot] ->
        :ets.insert(table, {"snapshot build", :ok, micro.(measurements.duration)})
        :ets.insert(table, {"snapshot reply copy", :ok, micro.(measurements.reply)})

      _ ->
        label = "#{metadata.operation} (handler)"
        :ets.insert(table, {label, metadata.outcome, micro.(measurements.duration)})
    end
  end,
  nil
)

depths = :ets.new(:depths, [:public, :duplicate_bag])
running = :atomics.new(1, [])
:atomics.put(running, 1, 1)

sampler =
  spawn(fn ->
    Stream.repeatedly(fn ->
      if :atomics.get(running, 1) == 1 do
        case Process.info(server, :message_queue_len) do
          {:message_queue_len, n} -> :ets.insert(depths, {:depth, n})
          nil -> :ok
        end

        Process.sleep(2)
        :cont
      else
        :halt
      end
    end)
    |> Enum.find(&(&1 == :halt))
  end)

deadline = System.monotonic_time(:microsecond) + seconds * 1_000_000

# Readers time their own calls: the owner reports handler duration only, and each
# worker keeps a private list so no shared table sits on the measured path.
reading =
  for reader <- 1..readers do
    mine = Enum.at(tokens, rem(reader - 1, length(tokens)))

    Task.async(fn ->
      Stream.repeatedly(fn -> System.monotonic_time(:microsecond) end)
      |> Enum.reduce_while([], fn started, taken ->
        if started < deadline do
          GameServer.snapshot(mine, server)
          taken = [System.monotonic_time(:microsecond) - started | taken]
          think.(read_think_ms)
          {:cont, taken}
        else
          {:halt, taken}
        end
      end)
    end)
  end

# Writers exercise the commit path — ledger reconciliation included — by alternating a
# draw and its repayment, the cheapest pair that is always valid against fresh credit.
# Each writer drives its own company: concurrent draws against one company would contend
# on that company's row and measure the conflict path instead of the commit path.
writing =
  for w <- 1..writers do
    mine = Enum.at(tokens, rem(w - 1, length(tokens)))
    command = fn id, payload -> GameServer.command(mine, id, payload, server) end

    Task.async(fn ->
      Stream.iterate(0, &(&1 + 1))
      |> Enum.reduce_while(0, fn n, committed ->
        if System.monotonic_time(:microsecond) < deadline do
          case command.("load-#{w}-#{n}", %{"action" => "borrow", "amount" => 100_000}) do
            {:ok, %{"loan_id" => loan}} ->
              think.(think_ms)
              command.("load-#{w}-#{n}-repay", %{"action" => "repay", "loan" => loan})
              think.(think_ms)
              {:cont, committed + 2}

            _ ->
              think.(think_ms)
              {:cont, committed}
          end
        else
          {:halt, committed}
        end
      end)
    end)
  end

latencies = reading |> Task.await_many(:infinity) |> List.flatten()
commits = writing |> Task.await_many(:infinity) |> Enum.sum()
:atomics.put(running, 1, 0)
Process.sleep(20)
Process.exit(sampler, :kill)

percentile = fn sorted, q ->
  Enum.at(sorted, min(length(sorted) - 1, trunc(q * length(sorted))))
end

reads = length(latencies)
arrivals = (reads + commits) / seconds

IO.puts(
  "reads #{reads} (#{Float.round(reads / seconds, 1)}/s), " <>
    "commits #{commits} (#{Float.round(commits / seconds, 1)}/s)\n"
)

row = fn label, values ->
  sorted = Enum.sort(values)

  IO.puts(
    String.pad_trailing(label, 20) <>
      String.pad_leading(to_string(length(sorted)), 8) <>
      String.pad_leading(:erlang.float_to_binary(percentile.(sorted, 0.50), decimals: 2), 9) <>
      String.pad_leading(:erlang.float_to_binary(percentile.(sorted, 0.95), decimals: 2), 9) <>
      String.pad_leading(:erlang.float_to_binary(percentile.(sorted, 0.99), decimals: 2), 9) <>
      String.pad_leading(:erlang.float_to_binary(Enum.max(sorted), decimals: 2), 9)
  )
end

IO.puts(
  String.pad_trailing("measurement (ms)", 20) <>
    String.pad_leading("n", 8) <>
    String.pad_leading("p50", 9) <>
    String.pad_leading("p95", 9) <> String.pad_leading("p99", 9) <> String.pad_leading("max", 9)
)

row.("snapshot round trip", Enum.map(latencies, &(&1 / 1000)))

:ets.tab2list(table)
|> Enum.filter(fn {_, outcome, _} -> outcome == :ok end)
|> Enum.group_by(fn {operation, _, _} -> operation end, fn {_, _, micro} -> micro / 1000 end)
|> Enum.sort_by(fn {_, values} -> -length(values) end)
|> Enum.each(fn {label, values} -> row.(label, values) end)

# Every span above is work done inside the one owner process, so their sum over the run
# is the fraction of that process which is busy. Only instrumented work counts, so this
# is a floor: garbage collection and uninstrumented callbacks are not in it.
busy =
  :ets.tab2list(table)
  |> Enum.map(fn {_, _, micro} -> micro end)
  |> Enum.sum()

sampled = :ets.tab2list(depths) |> Enum.map(fn {:depth, n} -> n end)
mean_depth = Enum.sum(sampled) / length(sampled)

IO.puts("""

Round trip is client call to reply; the rows above are time inside the owner and
exclude mailbox waiting. The two are not subtractable.

Owner busy at least #{Float.round(busy / (seconds * 10_000), 1)}% of the run.

Mean wait by Little's law (mean depth / arrival rate): \
#{Float.round(mean_depth / arrivals * 1000, 2)} ms \
(depth #{Float.round(mean_depth, 1)} of #{readers + writers} possible, \
#{Float.round(arrivals, 0)} arrivals/s)\
""")
