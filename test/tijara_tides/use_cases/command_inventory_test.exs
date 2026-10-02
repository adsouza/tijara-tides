defmodule TijaraTides.UseCases.CommandInventoryTest do
  use ExUnit.Case, async: true
  alias TijaraTides.CommandFuzzer.Inventory

  test "every dispatch action including locale and bound buy/sell is classified" do
    assert Inventory.commands() == Inventory.command_contracts() |> Map.keys() |> MapSet.new()

    changed =
      File.read!("lib/tijara_tides/domain/commands.ex")
      |> String.replace("\"action\" => \"invite\"", "\"action\" => \"new_action\"")

    refute Inventory.commands(changed) == Inventory.commands()
  end

  test "every literal form event has a web contract or explicit scoped exclusion" do
    assert Inventory.forms() == Inventory.form_contracts() |> Map.keys() |> MapSet.new()

    for path <- Path.wildcard("lib/tijara_tides_web/**/*.{ex,heex}") do
      refute File.read!(path) =~ ~r/phx-submit=\{/, "Classify dynamic form in #{path}"
    end
  end
end
