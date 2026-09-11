defmodule TijaraTides.PortCargoMarketBoundaryTest do
  use ExUnit.Case, async: true

  test "only the PortCargoMarket implementation writes market rows" do
    owned = ~w(markets)
    files = Path.wildcard("lib/tijara_tides/domain/**/*.ex")

    for file <- files,
        not String.contains?(file, "/port_cargo_market/") and
          not String.ends_with?(file, "/port_cargo_market.ex") do
      {_ast, calls} =
        file
        |> File.read!()
        |> Code.string_to_quoted!()
        |> Macro.prewalk([], fn
          {operation, _, [_state, kind | _]} = node, acc
          when operation in [:put, :delete] and is_binary(kind) ->
            {node, [kind | acc]}

          {{:., _, [_module, operation]}, _, [_state, kind | _]} = node, acc
          when operation in [:put, :delete] and is_binary(kind) ->
            {node, [kind | acc]}

          {operation, _, [kind | _]} = node, acc
          when operation in [:put, :delete] and is_binary(kind) ->
            {node, [kind | acc]}

          node, acc ->
            {node, acc}
        end)

      assert Enum.filter(calls, &(&1 in owned)) == [],
             "#{file} bypasses the PortCargoMarket aggregate"
    end
  end
end
