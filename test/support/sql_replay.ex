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

  def with_world(fun) do
    world = Ecto.UUID.generate()
    child = {GameServer, world}

    server =
      start_supervised!(
        Supervisor.child_spec(
          {GameServer,
           name: nil, enabled: true, world_id: world, tick_ms: 86_400_000, wall_clock: fn -> 1 end},
          id: child
        )
      )

    try do
      {:ok, code} = GameServer.seed(server)
      fun.(%{server: server, world: world, child: child, code: code})
    after
      assert :ok = stop_supervised(child)
      refute Process.alive?(server)
    end
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
          ~w(accounts companies ships warehouses ship_instructions route_stops route_rules exchange_orders loans markdown_presets) do
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
