defmodule TijaraTides.AutomationArchitectureTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{Fleet, LiquidationPool, VisitBudget, DepartureRequest, RemoteLink}

  alias TijaraTides.Domain.Services.{
    RouteEditing,
    DepartureFunding,
    LinkedOrders,
    Exchange,
    RemoteOrderSettlement,
    LiquidationSettlement,
    WarehouseLiquidation,
    FinancialSettlement
  }

  @orchestration [
    RouteEditing,
    DepartureFunding,
    LinkedOrders,
    Exchange,
    RemoteOrderSettlement,
    LiquidationSettlement,
    WarehouseLiquidation,
    Fleet
  ]

  # Compiled references resolve aliases, imports, delegates and remote captures;
  # checking source strings alone would miss renamed or imported back edges.
  defp dependencies(module) do
    Code.ensure_loaded!(module)
    # Locate the on-disk module also when coverage replaces the loaded code.
    beam = :code.where_is_file(~c"#{module}.beam")
    {:ok, {^module, [imports: imports]}} = :beam_lib.chunks(beam, [:imports])
    imports |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
  end

  defp service_dependencies(module),
    do:
      Enum.filter(
        dependencies(module),
        &String.starts_with?(Atom.to_string(&1), "Elixir.TijaraTides.Domain.Services.")
      )

  test "automation dependencies point from coordinators to settlement operations" do
    for {module, allowed} <- [
          {Fleet, [FinancialSettlement]},
          {DepartureFunding, [FinancialSettlement, LinkedOrders]},
          {LinkedOrders, [Exchange]},
          {Exchange, [RemoteOrderSettlement, LiquidationSettlement]},
          {RemoteOrderSettlement, []},
          {LiquidationSettlement, []}
        ] do
      assert service_dependencies(module) -- allowed == [],
             "#{inspect(module)} calls a higher-level service: #{inspect(service_dependencies(module) -- allowed)}"
    end
  end

  test "the targeted fleet and automation orchestration graph has no cycles" do
    graph =
      Map.new(@orchestration, fn module ->
        {module, Enum.filter(dependencies(module), &(&1 in @orchestration))}
      end)

    assert DepartureFunding in graph[RouteEditing]
    assert LinkedOrders in graph[RouteEditing]
    assert Fleet in graph[DepartureFunding]
    assert RemoteOrderSettlement in graph[Exchange]

    for module <- @orchestration, do: acyclic!(module, graph, [])
  end

  defp acyclic!(module, graph, path) do
    refute module in path, "Orchestration cycle: #{inspect(Enum.reverse([module | path]))}"
    for next <- graph[module], do: acyclic!(next, graph, [module | path])
  end

  test "reservation models cannot call world adapters, row codecs or workflows" do
    for module <- [LiquidationPool, VisitBudget, DepartureRequest, RemoteLink] do
      project_calls =
        Enum.filter(
          dependencies(module),
          &String.starts_with?(Atom.to_string(&1), "Elixir.TijaraTides.")
        )

      assert project_calls == [], "#{inspect(module)} is coupled to #{inspect(project_calls)}"

      for {function, arity} <- [from_row: 1, to_row: 1, from_world: 2, store: 2] do
        refute function_exported?(module, function, arity)
      end
    end
  end

  test "the route component consumes prepared options without reading receiving policy fields" do
    source = File.read!("lib/tijara_tides_web/components/ship_route_editor.ex")
    assert source =~ "@model.link_warehouses"
    refute source =~ "@model.warehouses"

    for field <- ~w(expires_ms award_grace storage company_id) do
      refute source =~ ~s(warehouse["#{field}"]),
             "Route component reads receiving policy field #{field}"
    end
  end
end
