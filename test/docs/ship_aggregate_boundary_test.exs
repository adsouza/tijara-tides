defmodule TijaraTides.ShipAggregateBoundaryTest do
  use ExUnit.Case, async: true

  test "only the Ship implementation writes ship-owned rows" do
    owned = ~w(ships ship_routes route_stops route_rules ship_instructions visit_plans)
    files = Path.wildcard("lib/tijara_tides/domain/**/*.ex")

    for file <- files,
        not String.contains?(file, "/ship/") and not String.ends_with?(file, "/ship.ex") do
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

      assert Enum.filter(calls, &(&1 in owned)) == [], "#{file} bypasses the Ship aggregate"
    end
  end
end
