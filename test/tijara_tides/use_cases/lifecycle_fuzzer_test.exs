defmodule TijaraTides.UseCases.LifecycleFuzzerTest do
  use ExUnit.Case, async: false
  use ExUnitProperties
  alias TijaraTides.CommandFuzzer.{Runner, Scenarios, Specs}

  defp parameters,
    do: fixed_map(%{quantity: integer(1..3), amount: integer(100..1000), mode: integer(0..1)})

  defp choices(n),
    do: list_of(tuple({integer(0..29), integer(0..20), integer(0..4)}), max_length: n)

  for family <- Scenarios.families() do
    @family family
    test "fixed #{@family} paths are replayable under four independent seeds" do
      for seed <- 1..4 do
        state = :rand.seed_s(:exsss, {seed, seed + 17, seed + 31})
        {quantity, state} = :rand.uniform_s(3, state)
        {amount, state} = :rand.uniform_s(901, state)
        p = %{quantity: quantity, amount: amount + 99, mode: rem(seed, 2)}
        size = length(Scenarios.prefix(@family, p))

        {values, _} =
          Enum.map_reduce(1..(60 - size), state, fn _, state ->
            {x, state} = :rand.uniform_s(30, state)
            {{x - 1, rem(x, 21), rem(x, 5)}, state}
          end)

        suffix = Specs.suffix(values, size)
        a = Runner.pure(@family, p, suffix, limit: 60)
        b = Runner.pure(@family, p, suffix, limit: 60)
        assert a.stats == b.stats
        assert a.model == b.model
        assert a.game.entities == b.game.entities
      end
    end

    property "#{@family} shrinking retains the essential lifecycle" do
      check all(
              p <- parameters(),
              values <- choices(30 - 11),
              max_runs: 20,
              max_shrinking_steps: 100
            ) do
        size = length(Scenarios.prefix(@family, p))
        values = Enum.take(values, 30 - size)
        r = Runner.pure(@family, p, Specs.suffix(values, size))
        assert r.stats.accepted >= 5
      end
    end
  end

  property "broad command exploration mixes valid commands and targeted violations" do
    check all(values <- choices(25), max_runs: 20, max_shrinking_steps: 100) do
      r = Runner.pure(:broad, %{quantity: 1, amount: 100, mode: 0}, Specs.suffix(values, 5, true))
      assert r.stats.accepted >= 5
    end
  end
end
