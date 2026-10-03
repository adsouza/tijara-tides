defmodule TijaraTides.UseCases.CommandInventoryTest do
  use ExUnit.Case, async: true
  alias TijaraTides.CommandFuzzer.Inventory
  alias TijaraTides.FormFields

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

  test "every field a form or click sends is read by its event handler" do
    assert FormFields.unread() == []
  end

  test "every form field is admitted by one of its actions or converted by its handler" do
    assert FormFields.dropped() == []
    forms = FormFields.forms()

    # A schema that loses a field the form sends is detected, not silently dropped.
    narrowed = fn
      %{"action" => "markdown_preset_save"} -> ~w(action preset markdowns price_floor)
      payload -> TijaraTides.UseCases.CommandPayload.admitted(payload)
    end

    assert [{"exchange", where, "name"}] =
             FormFields.dropped(
               forms,
               File.read!("lib/tijara_tides_web/live/game_live.ex"),
               narrowed
             )

    assert where =~ "exchange_panel.ex"

    # A new field inside a component rendered by a submit form is attributed to that form.
    sources =
      Enum.map(FormFields.sources(), fn
        {"lib/tijara_tides_web/components/game/exchange_panel.ex" = path, source} ->
          widened =
            String.replace(
              source,
              ~s(<select name="min_grade"),
              ~s(<input name="probe" /><select name="min_grade")
            )

          refute widened == source
          {path, widened}

        other ->
          other
      end)

    assert sources
           |> FormFields.forms()
           |> FormFields.dropped()
           |> Enum.map(&elem(&1, 2))
           |> Enum.uniq() ==
             ["probe"]

    # A field the handler converts by value is not dropped even though no schema admits it.
    facts = FormFields.handler_facts()
    assert "reserve_dollars" in facts["auction"].explicit
    refute facts["report-page"].command?
    assert MapSet.new(~w(sail reroute)) == facts["sail"].actions
  end
end
