defmodule TijaraTides.Infrastructure.Persistence.CommitBudgetTest do
  use ExUnit.Case, async: false
  @moduletag :game_database
  alias TijaraTides.CompanyFixture
  alias TijaraTides.Infrastructure.GameServer
  alias TijaraTides.Infrastructure.Persistence.Repo

  # A whole tick commits inside one transaction, on one connection, under one timeout, so
  # the commit is priced in round trips rather than in query cost. These tests watch the
  # repository telemetry and fail when a statement starts repeating per row — the shape of
  # defect no assertion about behaviour can see, because the behaviour stays correct.
  @event [:tijara_tides, :infrastructure, :persistence, :repo, :query]

  # Known exceptions, each one statement per row today. Batching them is tracked as its own
  # work; deleting an entry here is what tightens this test once that lands.
  @unbatched ["UPDATE game_markets SET version=version+1", "SELECT post_game_journal"]

  # Bind parameters are capped per statement, so a batch may legitimately be chunked. No
  # commit in this test comes near that cap.
  @allowance 2

  setup_all do
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

    Ecto.Migrator.run(Repo, TijaraTides.TestMigrations.all(), :up, all: true, log: false)
    :ok
  end

  defp start_world do
    id = Ecto.UUID.generate()

    server =
      start_supervised!(
        Supervisor.child_spec(
          {GameServer, name: nil, enabled: true, world_id: id, tick_ms: 86_400_000},
          id: id
        )
      )

    {:ok, code} = GameServer.seed(server)
    {:ok, %{"session" => token}} = GameServer.redeem(code, server)

    {:ok, _} =
      CompanyFixture.command(
        token,
        "company",
        %{"action" => "company", "name" => "Budget", "port" => "Jakarta", "package" => "general"},
        server
      )

    ship = GameServer.snapshot(token, server).private["ships"] |> Map.keys() |> hd()
    :ok = GameServer.connect(token, server)
    %{server: server, token: token, ship: ship}
  end

  # The owner ticks on a timer it owns. Moving its last sample back is how a test buys world
  # time without sleeping for it.
  defp tick(server) do
    :sys.replace_state(server, fn state -> %{state | last_mono: state.last_mono - 120_000} end)
    send(server, :tick)
    :sys.get_state(server)
  end

  defp buy(world, request) do
    command = %{
      "action" => "buy",
      "ship" => world.ship,
      "good" => "lumber",
      "quantity" => 1,
      "limit" => 1_000_000,
      "destination" => "Singapore"
    }

    # Handling occupies the berth, so consecutive purchases need ticks between them.
    Enum.reduce_while(1..20, {:error, :never_ran}, fn _, _ ->
      case CompanyFixture.command(world.token, request, command, world.server) do
        {:ok, result} -> {:halt, {:ok, result}}
        {:error, _} = error -> tick(world.server) && {:cont, error}
      end
    end)
  end

  defp tally(fun) do
    counts = :ets.new(:tally, [:public, :set])
    handler = {__MODULE__, make_ref()}

    :telemetry.attach(
      handler,
      @event,
      fn _, _, meta, _ ->
        shape = meta.query |> String.replace(~r/\s+/, " ") |> String.slice(0, 60)
        :ets.update_counter(counts, shape, {2, 1}, {shape, 0})
      end,
      nil
    )

    fun.()
    :telemetry.detach(handler)
    Map.new(:ets.tab2list(counts))
  end

  defp laden(lots) do
    world = start_world()
    for n <- 1..lots, do: {:ok, _} = buy(world, "load-#{n}")
    tick(world.server)
    world
  end

  test "a tick writes no table one row at a time" do
    # A world with cargo aboard, so a per-row regression in the children path would show
    # here too and not only in the parent rows.
    world = laden(2)
    counts = tally(fn -> tick(world.server) end)

    repeated =
      counts
      |> Enum.reject(fn {shape, _} -> Enum.any?(@unbatched, &String.starts_with?(shape, &1)) end)
      |> Enum.filter(fn {_, count} -> count > @allowance end)

    assert repeated == [], "these statements repeat per row: #{inspect(repeated, pretty: true)}"
  end
end
