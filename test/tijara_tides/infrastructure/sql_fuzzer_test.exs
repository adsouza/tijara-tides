defmodule TijaraTides.Infrastructure.SqlFuzzerTest do
  use ExUnit.Case, async: false
  use ExUnitProperties
  @moduletag :game_database
  alias TijaraTides.CommandFuzzer.{Scenarios, Specs, SqlBackend}
  alias TijaraTides.Infrastructure.Persistence.{FinancialLedger, Repo}

  setup_all do
    TijaraTides.SqlReplay.repo()
  end

  defp audit(world), do: FinancialLedger.audit(Repo, world)

  defp run(family, p, suffix, limit),
    do: SqlBackend.run(family, p, suffix, &audit/1, limit: limit)

  for family <- Scenarios.families() do
    @family family
    test "two #{@family} SQL traces persist replay and recover" do
      for seed <- 1..2 do
        state = :rand.seed_s(:exsss, {seed, seed + 17, seed + 31})
        {quantity, state} = :rand.uniform_s(3, state)
        {amount, state} = :rand.uniform_s(901, state)
        p = %{quantity: quantity, amount: amount + 99, mode: rem(seed, 2)}
        size = length(Scenarios.prefix(@family, p))

        suffix =
          [%{op: :observe}, %{op: :replay}, %{op: :restart}] ++
            Specs.suffix(
              elem(
                Enum.map_reduce(1..(25 - size - 3), state, fn _, state ->
                  {choice, state} = :rand.uniform_s(30, state)
                  {{choice - 1, rem(choice, 21), 1}, state}
                end),
                0
              ),
              size + 3
            )

        r = run(@family, p, suffix, 25)
        assert r.stats.accepted >= 5
      end
    end

    property "#{@family} SQL property owns a fresh world and server for each shrink attempt" do
      check all(
              quantity <- integer(1..3),
              amount <- integer(100..1000),
              mode <- integer(0..1),
              values <-
                list_of(tuple({integer(0..29), integer(0..20), integer(0..4)}), max_length: 4),
              max_runs: 5,
              max_shrinking_steps: 20
            ) do
        p = %{quantity: quantity, amount: amount, mode: mode}
        size = length(Scenarios.prefix(@family, p))
        suffix = Specs.suffix(Enum.take(values, 15 - size), size)
        assert run(@family, p, suffix, 15).stats.accepted >= 5
      end
    end
  end

  test "failing SQL replay cleans up its own owner before a fresh case starts" do
    caller = self()

    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      assert_raise ExUnit.AssertionError, ~r/planted SQL invariant/, fn ->
        SqlBackend.run(
          :broad,
          %{quantity: 1, amount: 100, mode: 0},
          [],
          fn _world -> flunk("planted SQL invariant") end,
          started: fn c -> send(caller, {:failed_case, c.server, c.world}) end,
          artifact: "sql-cleanup"
        )
      end
    end)

    assert_receive {:failed_case, server, world}
    refute Process.alive?(server)

    r =
      SqlBackend.run(:broad, %{quantity: 1, amount: 100, mode: 0}, [], &audit/1,
        started: fn c -> send(caller, {:fresh_case, c.server, c.world}) end
      )

    assert r.stats.accepted == 5
    assert_receive {:fresh_case, fresh, fresh_world}
    refute fresh_world == world
    refute Process.alive?(fresh)
  end

  test "two broad SQL fuzz traces keep command receipts and recover without duplicate effects" do
    for seed <- 1..2 do
      suffix =
        Specs.suffix(Enum.map(1..7, &{&1 + seed, seed, rem(&1, 5)}), 5, true) ++
          [%{op: :observe}, %{op: :replay}, %{op: :restart}]

      assert run(:broad, %{quantity: 1, amount: 100, mode: 0}, suffix, 15).stats.accepted >= 5
    end
  end
end
