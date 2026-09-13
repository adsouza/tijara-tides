defmodule Docs.BerthBoundaryTest do
  use ExUnit.Case, async: true

  test "ship berth mutation is exposed only through named transitions" do
    Code.ensure_loaded!(TijaraTides.Domain.Ship)
    refute function_exported?(TijaraTides.Domain.Ship, :update_berth, 3)

    for {name, arity} <- [
          request_berth: 2,
          grant_berth: 2,
          admit_handling: 2,
          release_berth: 3,
          queue_trade: 2,
          cancel_pending_trade: 2
        ] do
      assert function_exported?(TijaraTides.Domain.Ship, name, arity)
    end
  end

  test "berth coordinator delegates admission instead of recounting capacity" do
    source = File.read!("lib/tijara_tides/domain/services/berth_allocation.ex")

    {_ast, calls} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {{:., _, [{:__aliases__, _, [:PortBerths]}, name]}, _, _} = node, calls ->
          {node, [name | calls]}

        node, calls ->
          {node, calls}
      end)

    assert :allocate in calls
    refute :capacity in calls
    refute :occupied? in calls
  end
end
