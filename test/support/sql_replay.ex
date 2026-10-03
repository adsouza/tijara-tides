defmodule TijaraTides.SqlReplay do
  @moduledoc "A world and owner per replay, including every property shrink attempt."
  use Boundary,
    deps: [
      TijaraTides.Domain,
      TijaraTides.Infrastructure,
      TijaraTides.UseCases,
      TijaraTides.CompanyFixture,
      Ecto,
      Ecto.Migrator
    ]

  import ExUnit.Callbacks
  import ExUnit.Assertions
  alias TijaraTides.Infrastructure.{GameServer, Persistence.Repo, Persistence.GameStore}

  def repo do
    port = System.fetch_env!("TIJARA_TEST_DB_PORT") |> String.to_integer()

    start_supervised!(
      {Repo,
       hostname: "127.0.0.1",
       port: port,
       username: "postgres",
       database: "postgres",
       ssl: false,
       pool_size: 4}
    )

    Ecto.Migrator.run(Repo, apply(TijaraTides.TestMigrations, :all, []), :up,
      all: true,
      log: false
    )

    :ok
  end

  def with_world(fun, opts \\ []) do
    world = Ecto.UUID.generate()
    child = {GameServer, world}

    opts =
      Keyword.merge(
        [name: nil, enabled: true, world_id: world, tick_ms: 86_400_000, wall_clock: fn -> 1 end],
        opts
      )

    server =
      start_supervised!(
        Supervisor.child_spec(
          {GameServer, opts},
          id: child
        )
      )

    try do
      {:ok, code} = GameServer.seed(server)
      fun.(%{server: server, world: world, child: child, code: code, opts: opts})
    after
      assert :ok = stop_supervised(child)
      refute Process.alive?(server)
    end
  end

  def company(c) do
    {:ok, %{"session" => token}} = GameServer.redeem(c.code, c.server)

    assert {:ok, %{"company_id" => company}} =
             TijaraTides.CompanyFixture.command(
               token,
               "fixture-company",
               %{
                 "action" => "company",
                 "name" => "Replay company",
                 "port" => "Jakarta",
                 "package" => "general"
               },
               c.server
             )

    game = :sys.get_state(c.server).game
    account = game.entities["companies"][company]["account_id"]

    ships =
      game.entities["ships"] |> Map.values() |> Enum.sort_by(& &1["id"]) |> Enum.map(& &1["id"])

    Map.merge(c, %{token: token, company: company, account: account, ships: ships})
  end

  # Explicit fixture/adapter boundary, not a replacement for ordinary server commands.
  def persist(c, next) do
    before = :sys.get_state(c.server).game

    prepared =
      TijaraTides.UseCases.CommitPreparation.prepare(before, %{
        next
        | revision: before.revision + 1
      })

    assert {:ok, :ok} = GameStore.commit(Repo, c.world, before.epoch, before, prepared)
    accepted = TijaraTides.UseCases.CommitPreparation.accepted(prepared)

    :sys.replace_state(c.server, fn state ->
      %{
        state
        | game: accepted,
          projection: TijaraTides.UseCases.WorldProjection.build(accepted, state.catalogue)
      }
    end)

    accepted
  end

  def restart(c) do
    assert :ok = stop_supervised(c.child)
    refute Process.alive?(c.server)
    server = start_supervised!(Supervisor.child_spec({GameServer, c.opts}, id: c.child))
    assert GameServer.readiness(server) == :ready
    %{c | server: server}
  end

  def command(c, token, id, command) do
    assert {:ok, reply} = GameServer.command(token, id, command, c.server)
    assert GameServer.readiness(c.server) == :ready
    reply
  end

  def advance(server, ms) do
    :sys.replace_state(server, fn state ->
      %{state | active: true, last_mono: System.monotonic_time(:millisecond) - ms}
    end)

    send(server, :tick)
    :sys.get_state(server)
    assert GameServer.readiness(server) == :ready
  end

  def assert_rows(c, expected) do
    restored = reload(c)

    for table <-
          ~w(accounts companies ships warehouses ship_instructions route_stops route_rules exchange_orders loans markdown_presets departure_requests visit_budgets remote_links warehouse_liquidations operating_bills loan_installments guarantees) do
      rows = Map.get(expected.entities, table, %{})
      actual = Map.get(restored.entities, table, %{})
      assert Map.keys(actual) |> Enum.sort() == Map.keys(rows) |> Enum.sort(), table

      for {id, row} <- rows do
        for {key, value} <- row do
          assert actual[id][key] == value, "#{table}/#{id}/#{key} changed on reload"
        end
      end
    end

    restored
  end

  def reload(c) do
    game = :sys.get_state(c.server).game
    assert {:ok, restored} = GameStore.reload(Repo, c.world, game)
    restored
  end
end
