defmodule TijaraTides.ShipAggregateBoundaryTest do
  use ExUnit.Case, async: true

  test "only the Ship implementation writes ship-owned rows" do
    owned = ~w(ships ship_routes route_stops route_rules ship_instructions visit_plans)
    files = Path.wildcard("lib/tijara_tides/domain/**/*.ex")

    for file <- files,
        not String.contains?(file, "/ship_world/") and
          not String.ends_with?(file, "/ship_world.ex") do
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

  test "the typed ship model cannot access world state or codecs" do
    for file <-
          ~w(lib/tijara_tides/domain/ship.ex lib/tijara_tides/domain/ship/cargo_batch.ex lib/tijara_tides/domain/ship/route_plan.ex) do
      ast = file |> File.read!() |> Code.string_to_quoted!()

      Macro.prewalk(ast, fn
        {:__aliases__, _, parts} = node ->
          assert Enum.all?(
                   parts,
                   &(&1 not in [
                       :State,
                       :ReadState,
                       :ShipWorld,
                       :Rows,
                       :CargoRows,
                       :Fleet,
                       :Services
                     ])
                 ),
                 file

          node

        node ->
          node
      end)
    end

    Code.ensure_loaded!(TijaraTides.Domain.Ship)

    for {name, arity} <- [from_row: 1, to_row: 1, from_world: 2, store: 2] do
      refute function_exported?(TijaraTides.Domain.Ship, name, arity)
    end
  end
end
