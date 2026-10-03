defmodule TijaraTides.UseCases.ExtendedFuzzerTest do
  use ExUnit.Case, async: false
  use ExUnitProperties
  @moduletag :extended_fuzzer
  alias TijaraTides.CommandFuzzer.{Artifacts, Runner, Specs}

  property "opt-in 100-case 60-action discovery sweep and capped corpus" do
    check all(
            values <-
              list_of(tuple({integer(0..29), integer(0..20), integer(0..4)}), max_length: 55),
            max_runs: 100,
            max_shrinking_steps: 100
          ) do
      Runner.pure(:broad, %{quantity: 1, amount: 100, mode: 0}, Specs.suffix(values, 5, true),
        limit: 60
      )
    end
  end

  test "versioned corpus replays without seed search" do
    for path <- Path.wildcard("cover/command-fuzzer-corpus/*.etf") |> Enum.take(50) do
      record = Artifacts.read!(path)
      Runner.pure(record.family, record.parameters, record.suffix, limit: 60)
    end
  end
end
