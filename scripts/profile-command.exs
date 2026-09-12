# What a single command spends its time on.
#
# Command cost is flat across a twelve-fold range of world size, so it is per-transaction
# overhead rather than data volume. This attributes it: every statement Ecto issues while
# commands run is grouped by shape and divided by the command count, and the owner's own
# span is measured alongside so the part that is not SQL is visible as the remainder.
#
# Commands run sequentially here, so statements need no correlation to be attributed.
#
# Run with scripts/profile-command.py, which supplies a disposable PostgreSQL.
alias TijaraTides.Infrastructure.GameServer
alias TijaraTides.Infrastructure.Persistence.Repo

companies = String.to_integer(System.get_env("LOAD_COMPANIES", "150"))
max_ships = String.to_integer(System.get_env("LOAD_SHIPS", "6"))
rounds = String.to_integer(System.get_env("LOAD_COMMANDS", "100"))
port = System.fetch_env!("TIJARA_TEST_DB_PORT") |> String.to_integer()

Application.put_env(:tijara_tides, :audit_mutations, false)

{:ok, _} =
  Repo.start_link(
    hostname: "127.0.0.1",
    port: port,
    username: "postgres",
    database: "postgres",
    ssl: false,
    pool_size: 8
  )

Ecto.Migrator.run(
  Repo,
  Application.app_dir(:tijara_tides, "priv/repo/migrations"),
  :up,
  all: true,
  log: false
)

world = Ecto.UUID.generate()

# A very long tick keeps progression out of the measurement entirely.
{:ok, server} =
  GameServer.start_link(name: nil, enabled: true, world_id: world, tick_ms: 86_400_000)

tokens =
  for company <- 1..companies do
    {:ok, code} = GameServer.seed(server)
    {:ok, %{"session" => token}} = GameServer.redeem_for_device(code, GameServer.token(), server)
    run = fn id, payload -> GameServer.command(token, id, payload, server) end

    {:ok, _} =
      run.("company-#{company}", %{
        "action" => "company",
        "name" => "Profile #{company}",
        "port" => "Jakarta",
        "package" => "general"
      })

    hulls = rem(company - 1, max_ships) + 1
    {:ok, _} = run.("credit-#{company}", %{"action" => "borrow", "amount" => hulls * 4_100_000})

    for hull <- 1..hulls do
      {:ok, _} =
        run.("ship-#{company}-#{hull}", %{
          "action" => "purchase_ship",
          "class" => "freighter",
          "port" => "Jakarta",
          "price_limit" => 4_000_000
        })
    end

    token
  end

token = hd(tokens)
command = fn id, payload -> GameServer.command(token, id, payload, server) end

statements = :ets.new(:statements, [:public, :duplicate_bag])
spans = :ets.new(:spans, [:public, :duplicate_bag])

# Ecto derives its event prefix from the repository module unless configured otherwise.
prefix = Repo.config()[:telemetry_prefix] || [:tijara_tides, :infrastructure, :persistence, :repo]

:telemetry.attach_many(
  "profile-command",
  [prefix ++ [:query], [:tijara_tides, :operation, :stop]],
  fn
    [:tijara_tides, :operation, :stop], %{duration: duration}, %{operation: :command}, _ ->
      :ets.insert(spans, {:command, System.convert_time_unit(duration, :native, :microsecond)})

    [:tijara_tides, :operation, :stop], _, _, _ ->
      :ok

    _query_event, measurements, metadata, _ ->
      micro = &System.convert_time_unit(&1 || 0, :native, :microsecond)

      # The handler runs in the process that issued the query, so it must do no work
      # beyond the insert: normalising the text here would land inside the very span
      # being measured. Statements are grouped by shape at reporting time instead.
      :ets.insert(
        statements,
        {metadata.query, micro.(measurements[:total_time]), micro.(measurements[:queue_time])}
      )
  end,
  nil
)

# Warm the connection pool and the query cache before anything is recorded.
for n <- 1..5 do
  {:ok, %{"loan_id" => loan}} =
    command.("warm-#{n}", %{"action" => "borrow", "amount" => 100_000})

  {:ok, _} = command.("warm-#{n}-repay", %{"action" => "repay", "loan" => loan})
end

:ets.delete_all_objects(statements)
:ets.delete_all_objects(spans)

started = System.monotonic_time(:microsecond)

for n <- 1..rounds do
  {:ok, %{"loan_id" => loan}} = command.("cmd-#{n}", %{"action" => "borrow", "amount" => 100_000})
  {:ok, _} = command.("cmd-#{n}-repay", %{"action" => "repay", "loan" => loan})
end

wall = System.monotonic_time(:microsecond) - started
commands = rounds * 2

owner = :ets.tab2list(spans) |> Enum.map(&elem(&1, 1)) |> Enum.sum()
rows = :ets.tab2list(statements)
sql = rows |> Enum.map(&elem(&1, 1)) |> Enum.sum()
queue = rows |> Enum.map(&elem(&1, 2)) |> Enum.sum()

IO.puts("""
world #{String.slice(world, 0, 8)}: #{companies} companies, #{commands} commands measured

per command                      value
owner span                  #{String.pad_leading("#{Float.round(owner / commands / 1000, 2)} ms", 10)}
  of which SQL              #{String.pad_leading("#{Float.round(sql / commands / 1000, 2)} ms", 10)}\
  (#{round(sql / owner * 100)}% of the span)
  of which pool queueing    #{String.pad_leading("#{Float.round(queue / commands / 1000, 2)} ms", 10)}
  statements                #{String.pad_leading("#{Float.round(length(rows) / commands, 1)}", 10)}
client round trip           #{String.pad_leading("#{Float.round(wall / commands / 1000, 2)} ms", 10)}
""")

IO.puts(
  String.pad_trailing("statement", 54) <>
    String.pad_leading("n/cmd", 7) <>
    String.pad_leading("ms/cmd", 9) <> String.pad_leading("%", 6)
)

# A statement's text varies only in its bind placeholders here, so the leading clause is
# enough to group by, and keeps INSERT batches of different widths together.
shape = fn query ->
  query |> String.replace(~r/\s+/, " ") |> String.trim() |> String.slice(0, 52)
end

rows
|> Enum.group_by(&shape.(elem(&1, 0)), &elem(&1, 1))
|> Enum.sort_by(fn {_, times} -> -Enum.sum(times) end)
|> Enum.each(fn {text, times} ->
  total = Enum.sum(times)

  IO.puts(
    String.pad_trailing(text, 54) <>
      String.pad_leading("#{Float.round(length(times) / commands, 1)}", 7) <>
      String.pad_leading("#{Float.round(total / commands / 1000, 2)}", 9) <>
      String.pad_leading("#{round(total / owner * 100)}", 6)
  )
end)

IO.puts("""

Percentages are of the owner's span, so they sum to the SQL share; the remainder is
work on the BEAM. Ticks are excluded by a tick interval longer than the run.\
""")
