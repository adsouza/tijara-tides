defmodule TijaraTides.AutomationArchitectureTest do
  use ExUnit.Case, async: true

  alias TijaraTides.Domain.{
    AccountWorld,
    ShipWorld,
    WarehouseWorld,
    AutomationWorld,
    Fleet,
    LiquidationPool,
    VisitBudget,
    DepartureRequest,
    RemoteLink
  }

  alias TijaraTides.Domain.Services.{
    ShipLifecycle,
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
    ShipLifecycle,
    RouteEditing,
    DepartureFunding,
    LinkedOrders,
    Exchange,
    RemoteOrderSettlement,
    LiquidationSettlement,
    WarehouseLiquidation,
    Fleet,
    ShipWorld,
    ShipWorld.RoutePlans,
    ShipWorld.VisitOrders,
    AutomationWorld
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
          {Fleet, [FinancialSettlement, ShipLifecycle]},
          {DepartureFunding, [FinancialSettlement, LinkedOrders]},
          {LinkedOrders, [Exchange]},
          {Exchange, [RemoteOrderSettlement, LiquidationSettlement]},
          {RemoteOrderSettlement, []},
          {LiquidationSettlement, []},
          {ShipWorld, []},
          {ShipLifecycle, [LinkedOrders, LiquidationSettlement]}
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
    assert ShipWorld.RoutePlans in graph[LinkedOrders]
    assert LinkedOrders in graph[ShipLifecycle]
    assert RemoteOrderSettlement in graph[Exchange]

    for module <- @orchestration, do: acyclic!(module, graph, [])
  end

  test "ShipWorld has no transitive workflow back edge, including adapters outside the service inventory" do
    reachable = project_dependencies(ShipWorld, MapSet.new())
    refute ShipWorld in reachable
    refute Fleet in dependencies(WarehouseWorld)
  end

  defp project_dependencies(module, visited), do: walk_dependencies([module], visited, [])
  defp walk_dependencies([], _visited, edges), do: Enum.uniq(edges)

  defp walk_dependencies([module | rest], visited, edges) do
    if module in visited do
      walk_dependencies(rest, visited, edges)
    else
      direct =
        Enum.filter(
          dependencies(module),
          &String.starts_with?(Atom.to_string(&1), "Elixir.TijaraTides.Domain.")
        )

      walk_dependencies(direct ++ rest, MapSet.put(visited, module), direct ++ edges)
    end
  end

  defp acyclic!(module, graph, path) do
    refute module in path, "Orchestration cycle: #{inspect(Enum.reverse([module | path]))}"
    for next <- graph[module], do: acyclic!(next, graph, [module | path])
  end

  test "commands run no reconcile sweep; only clock-driven tick passes remain" do
    sweeps = [
      {Exchange, :reconcile, 1},
      {TijaraTides.Domain.Services.Auctions, :reconcile, 2},
      {TijaraTides.Domain.Services.WarehouseLeases, :advance, 2}
    ]

    {:ok, modules} = :application.get_key(:tijara_tides, :modules)

    callers =
      for module <- modules,
          String.starts_with?(Atom.to_string(module), "Elixir.TijaraTides.Domain."),
          beam = :code.where_is_file(~c"#{module}.beam"),
          beam != :non_existing,
          {:ok, {^module, [imports: imports]}} = :beam_lib.chunks(beam, [:imports]),
          call <- imports,
          call in sweeps,
          uniq: true,
          do: module

    # Exchange.advance and Auctions.advance call their passes locally.
    assert callers == [TijaraTides.Domain.Simulation]

    {:ok, {_, [imports: commands]}} =
      :beam_lib.chunks(:code.where_is_file(~c"#{TijaraTides.Domain.Commands}.beam"), [:imports])

    refute Enum.any?(commands, fn {_, function, _} ->
             function |> Atom.to_string() |> String.contains?("reconcile")
           end)
  end

  test "world roots never call up into coordinator services" do
    {:ok, modules} = :application.get_key(:tijara_tides, :modules)

    roots =
      for module <- modules,
          name = Atom.to_string(module),
          String.starts_with?(name, "Elixir.TijaraTides.Domain."),
          not String.contains?(name, ".Services."),
          Regex.match?(~r/World(\.|$)/, name),
          do: module

    assert WarehouseWorld in roots and AccountWorld.Dormancy in roots

    for root <- roots do
      services =
        Enum.filter(
          dependencies(root),
          &String.starts_with?(Atom.to_string(&1), "Elixir.TijaraTides.Domain.Services.")
        )

      assert services == [], "#{inspect(root)} calls coordinator services #{inspect(services)}"
    end
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
