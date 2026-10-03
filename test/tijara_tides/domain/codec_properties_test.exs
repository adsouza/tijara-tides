defmodule TijaraTides.Domain.CodecPropertiesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias TijaraTides.Domain.CodecCases

  for kind <- CodecCases.kinds() do
    property "#{kind} codec preserves independent semantic fields" do
      check all(
              amount <- integer(0..2_147_483_647),
              now <- integer(0..1_000_000_000),
              optional? <- boolean(),
              max_runs: 50,
              max_shrinking_steps: 100
            ) do
        %{codec: codec, row: row, defaults: defaults} =
          CodecCases.sample(unquote(kind), amount, now, optional?)

        decoded = CodecCases.decode(codec, row)
        assert CodecCases.facts(decoded) == Map.merge(defaults, row)
        assert CodecCases.encode(codec, decoded) == row
        assert CodecCases.decode(codec, CodecCases.encode(codec, decoded)) == decoded
      end
    end
  end

  test "codec boundary examples include zero, one and the signed SQL integer maximum" do
    for kind <- CodecCases.kinds(), amount <- [0, 1, 2_147_483_647], optional? <- [false, true] do
      %{codec: codec, row: row, defaults: defaults} =
        CodecCases.sample(kind, amount, 0, optional?)

      model = CodecCases.decode(codec, row)
      assert CodecCases.facts(model) == Map.merge(defaults, row)
      assert CodecCases.encode(codec, model) == row
    end
  end

  test "required omissions, unknown fields and malformed row containers are explicit errors" do
    for kind <- CodecCases.kinds() do
      %{codec: codec, row: row, defaults: defaults} = CodecCases.sample(kind, 100, 20, true)

      for key <- Map.keys(row) -- Map.keys(defaults) do
        assert_raise if(kind in [:auction, :account], do: ArgumentError, else: KeyError),
                     fn -> CodecCases.decode(codec, Map.delete(row, key)) end
      end

      assert_raise ArgumentError, fn -> CodecCases.decode(codec, Map.put(row, "surprise", 1)) end

      for wrong <- [[], false, 7, "row"] do
        error =
          cond do
            kind == :account and wrong == [] -> ArgumentError
            kind == :account -> FunctionClauseError
            true -> BadMapError
          end

        assert_raise error, fn -> CodecCases.decode(codec, wrong) end
      end
    end
  end

  test "legacy defaults are per-entity and explicit nil is preserved except documented account fallback" do
    for kind <- CodecCases.kinds() do
      %{codec: codec, row: row, defaults: defaults} = CodecCases.sample(kind, 100, 20, true)
      legacy = Map.drop(row, Map.keys(defaults))
      expected = Map.merge(defaults, legacy)
      assert CodecCases.facts(CodecCases.decode(codec, legacy)) == expected
    end

    %{codec: codec, row: row} = CodecCases.sample(:account, 100, 20, true)

    assert %{locale: "en", funding_policy: "wait"} =
             CodecCases.decode(codec, %{row | "locale" => nil, "funding_policy" => nil})

    %{codec: codec, row: row} = CodecCases.sample(:request, 100, 20, false)
    assert CodecCases.decode(codec, row).configured == nil
    assert CodecCases.decode(codec, row).window_deadline_ms == nil
  end
end
