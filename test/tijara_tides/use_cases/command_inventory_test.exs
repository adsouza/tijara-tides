defmodule TijaraTides.UseCases.CommandInventoryTest do
  use ExUnit.Case, async: true
  alias TijaraTides.CommandFuzzer.Inventory

  test "every dispatch action including locale and bound buy/sell is classified" do
    assert Inventory.commands() == Inventory.command_contracts() |> Map.keys() |> MapSet.new()

    changed =
      File.read!("lib/tijara_tides/domain/commands.ex")
      |> String.replace("\"action\" => \"invite\"", "\"action\" => \"new_action\"")

    refute Inventory.commands(changed) == Inventory.commands()

    assert_raise ArgumentError, ~r/Unresolved dynamic/, fn ->
      Inventory.commands("def dispatch(%{\"action\" => incoming}), do: incoming")
    end
  end

  test "route variants and backend harness operations have explicit scope" do
    assert Inventory.route_operations() == MapSet.new(Map.keys(Inventory.route_contracts()))
    source = File.read!("lib/tijara_tides/domain/ship_world/route_plans.ex")

    refute Inventory.route_operations(String.replace(source, "\"add_stop\"", "\"new_operation\"")) ==
             Inventory.route_operations()

    assert Inventory.harness_contracts().replay == [:sql]
    assert Inventory.harness_contracts().restart == [:sql]

    for {_action, contract} <- Inventory.command_contracts(),
        do: refute(contract.mode == :planned)
  end

  test "every literal form event has a web contract or explicit scoped exclusion" do
    assert Inventory.forms() == Inventory.form_contracts() |> Map.keys() |> MapSet.new()

    for path <- Path.wildcard("lib/tijara_tides_web/**/*.{ex,heex}") do
      refute File.read!(path) =~ ~r/phx-submit=\{/, "Classify dynamic form in #{path}"
    end
  end
end
