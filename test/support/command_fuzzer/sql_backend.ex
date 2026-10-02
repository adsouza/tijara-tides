defmodule TijaraTides.CommandFuzzer.SqlBackend do
  @moduledoc "Fresh committed world per replay, deterministic clocks, receipt/reload/restart checkpoints."
  import ExUnit.Assertions
  alias TijaraTides.CommandFuzzer.{Runner, Scenarios}
  alias TijaraTides.SqlReplay, as: Sql
  alias TijaraTides.Infrastructure.{GameServer, Persistence.Repo}

  def run(family, parameters, suffix, audit, opts \\ []) do
    {:ok, clock} = Agent.start_link(fn -> %{mono: 0, wall: 1} end)

    try do
      Sql.with_world(
        fn c ->
          c = Sql.company(c)
          game = :sys.get_state(c.server).game

          b = %{
            a: c.account,
            company_a: c.company,
            ship: Enum.at(c.ships, 0),
            ship_two: Enum.at(c.ships, 1),
            b_session: hash("secondary-fuzzer-session"),
            beneficiary_session: hash("beneficiary-fuzzer-session")
          }

          {fixture, catalogue, b} =
            Scenarios.fixture(game, :sys.get_state(c.server).catalogue, b, family)

          game = Sql.persist(c, fixture)
          Keyword.get(opts, :started, fn _ -> :ok end).(c)
          :sys.replace_state(c.server, &%{&1 | catalogue: catalogue})
          key = {__MODULE__, make_ref()}
          Process.put(key, c)

          tokens = %{
            b.a => c.token,
            b.b => "secondary-fuzzer-session",
            "beneficiary" => "beneficiary-fuzzer-session"
          }

          checkpoint = fn ->
            c = Process.get(key)
            assert GameServer.readiness(c.server) == :ready
            current = :sys.get_state(c.server).game
            Sql.assert_rows(c, current)
            assert :ok = audit.(c.world)
            current
          end

          backend = %{
            kind: :sql,
            command: fn _game, _cat, actor, payload, id ->
              c = Process.get(key)
              result = GameServer.command(Map.fetch!(tokens, actor), id, payload, c.server)
              current = checkpoint.()

              case result do
                {:ok, reply} ->
                  assert [[reply]] ==
                           Repo.query!(
                             "SELECT result FROM game_receipts WHERE world_id=$1 AND account_id=$2 AND request_id=$3",
                             [c.world, actor, id]
                           ).rows

                  {:ok, current, reply}

                error ->
                  error
              end
            end,
            tick: fn _game, _cat, elapsed ->
              c = Process.get(key)
              Agent.update(clock, &%{&1 | mono: &1.mono + elapsed})
              :sys.replace_state(c.server, &%{&1 | active: true})
              send(c.server, :tick)
              :sys.get_state(c.server)
              checkpoint.()
            end,
            observe: fn _game, _cat, _b -> checkpoint.() end,
            replay: fn _game, _cat, _b, last ->
              c = Process.get(key)
              revision = :sys.get_state(c.server).game.revision

              assert {:ok, last.reply} ==
                       GameServer.command(
                         Map.fetch!(tokens, last.actor),
                         last.id,
                         last.payload,
                         c.server
                       )

              current = checkpoint.()
              assert current.revision == revision
              current
            end,
            restart: fn _game, cat, _b ->
              c = Process.get(key)
              before = :sys.get_state(c.server).game
              c = Sql.restart(c)
              Process.put(key, c)
              :sys.replace_state(c.server, &%{&1 | catalogue: cat})
              restored = checkpoint.()
              # Compare persisted contract fields; codecs may add explicit nil/defaults.
              Sql.assert_rows(c, before)
              restored
            end
          }

          try do
            Runner.replay(game, catalogue, b, backend, family, parameters, suffix, opts)
          after
            c = Process.delete(key)
            # Outer Sql.with_world owns the child ID even after replacement.
            Process.put({__MODULE__, :last_server}, c.server)
          end
        end,
        monotonic_clock: fn -> Agent.get(clock, & &1.mono) end,
        wall_clock: fn -> Agent.get(clock, & &1.wall) end,
        auction_seed: fn -> "fuzzer-valuation-v1" end
      )
    after
      Agent.stop(clock)
      if server = Process.delete({__MODULE__, :last_server}), do: refute(Process.alive?(server))
    end
  end

  defp hash(token), do: GameServer.hash(token)
end
