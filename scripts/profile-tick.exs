# Phase breakdown for one world tick.
#
# The :progression telemetry covers far more than Simulation.advance/3: identity
# restore, lot allocation (which re-runs the whole pure operation when its batch is
# exhausted), reporting preparation, the SQL commit, and the public projection rebuild.
# This seeds a realistic world through the public API, then times each phase against
# the same starting state so the costs are comparable.
#
# Run with scripts/profile-tick.py, which supplies a disposable PostgreSQL.
alias TijaraTides.Domain.{Account, Fleet, PortCargoMarket, Simulation}
alias TijaraTides.Domain.Services.{AutomatedVisits, FinancialSettlement}
alias TijaraTides.Infrastructure.GameServer
alias TijaraTides.Infrastructure.Persistence.{GameStore, Repo}
alias TijaraTides.UseCases.{CommitPreparation, LotAllocation, WorldProjection}

companies = String.to_integer(System.get_env("LOAD_COMPANIES", "150"))
max_ships = String.to_integer(System.get_env("LOAD_SHIPS", "6"))
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

# A very long tick keeps the owner from advancing the world underneath the profile.
{:ok, server} =
  GameServer.start_link(name: nil, enabled: true, world_id: world, tick_ms: 86_400_000)

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
end

game = :sys.get_state(server).game
catalogue = GameServer.definitions().catalogue
ships = map_size(TijaraTides.Domain.ReadState.entities(game, "ships"))
markets = map_size(TijaraTides.Domain.ReadState.entities(game, "markets"))

# Long enough to cross the market replenishment interval, so the tick does real work.
elapsed = 150_000

IO.puts("""
world #{String.slice(world, 0, 8)}: #{companies} companies, #{ships} ships, #{markets} markets
advancing #{elapsed}ms of world time
""")

measure = fn label, fun ->
  {micro, result} = :timer.tc(fun)
  IO.puts(String.pad_trailing(label, 34) <> String.pad_leading("#{div(micro, 100) / 10} ms", 10))
  result
end

IO.puts("-- Simulation.advance/3, phase by phase (pure, no allocation retries)")
base = %{game | clock_ms: game.clock_ms + elapsed}
a = measure.("settle finances", fn -> FinancialSettlement.settle(base) end)
b = measure.("Fleet.advance", fn -> Fleet.advance(a, elapsed) end)
c = measure.("settle finances (again)", fn -> FinancialSettlement.settle(b) end)
d = measure.("PortCargoMarket.advance", fn -> PortCargoMarket.advance(c, catalogue) end)
e = measure.("AutomatedVisits.advance", fn -> AutomatedVisits.advance(d, catalogue) end)
_advanced = measure.("Account.expire_invitations", fn -> Account.expire_invitations(e) end)

IO.puts("\n-- whole tick, as the owner runs it")
attempts = :counters.new(1, [])
store = {TijaraTides.Infrastructure.Persistence.CommandStore, %{repo: Repo, world_id: world}}

allocated =
  measure.("Simulation.advance via LotAllocation", fn ->
    LotAllocation.run(game, store, fn fresh ->
      :counters.add(attempts, 1, 1)
      {:ok, Simulation.advance(fresh, elapsed, catalogue), %{}}
    end)
  end)

{:ok, changed, _} = allocated
runs = :counters.get(attempts, 1)

IO.puts(
  String.pad_trailing("  (allocation attempts)", 34) <>
    String.pad_leading("#{runs}x", 10) <> "  each a full re-run of the advance"
)

prepared =
  measure.("CommitPreparation.prepare", fn ->
    CommitPreparation.prepare(game, %{changed | revision: game.revision + 1})
  end)

measure.("WorldProjection.build", fn -> WorldProjection.build(prepared, catalogue) end)

events = length(Map.get(prepared, :journal, []))
rows = map_size(TijaraTides.Domain.ChangeSet.since(game, prepared))

IO.puts(
  String.pad_trailing("  (commit writes)", 34) <>
    String.pad_leading("#{rows} rows", 10) <> ", #{events} journal events"
)

measure.("GameStore.commit (SQL)", fn ->
  {:ok, :ok} = GameStore.commit(Repo, world, game.epoch, game, prepared, nil)
end)

IO.puts("""

Phase timings above are one sample each on a warm VM; they are for apportioning the
tick, not for absolute comparison. Rows under "whole tick" sum to roughly what the
:progression telemetry reports.\
""")
