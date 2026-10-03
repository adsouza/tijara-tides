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

  test "command discovery follows direct submissions and delegated helpers without cycles" do
    facts = FormFields.handler_facts()

    for event <- ~w(preview port-destination) do
      assert facts[event].command?
      assert facts[event].actions == MapSet.new(["plan_destination"])
    end

    source = """
    def handle_event("entry", params, socket), do: handle_event("submit", params, socket)
    def handle_event("submit", params, socket), do: remember(socket, params)
    def handle_event("display", params, socket), do: display(socket, params)
    def handle_event("qualified", _, socket) do
      TijaraTides.UseCases.Game.command(socket.token, "request", %{"action" => "borrow"})
    end
    def handle_event("unrelated", _, socket), do: Other.command(socket, "request", %{})
    defp remember(socket, params) do
      cycle(socket, params)
      Game.command(socket.token, "request", %{"action" => "plan_destination"})
    end
    defp cycle(socket, params), do: remember(socket, params)
    defp display(socket, params), do: {socket, params}
    """

    discovered = FormFields.handler_facts(source)
    assert discovered["entry"].command?
    assert discovered["submit"].command?
    assert discovered["entry"].actions == MapSet.new(["plan_destination"])
    refute discovered["display"].command?
    assert discovered["qualified"].command?
    assert discovered["qualified"].actions == MapSet.new(["borrow"])
    refute discovered["unrelated"].command?
  end

  test "command click producers retain separate template and rendered identities" do
    records = Enum.filter(FormFields.forms(), &(&1.event == "cancel-instruction"))

    assert Enum.sort(Enum.map(records, & &1.id_prefix)) ==
             ["fleet-cancel-instruction-", "route-cancel-instruction-"]

    html = """
    <button id="fleet-cancel-instruction-order" phx-click="cancel-instruction"
            phx-value-id="order">Cancel instruction</button>
    <button id="route-cancel-instruction-order" phx-click="cancel-instruction"
            phx-value-id="order">Cancel route order</button>
    """

    controls = TijaraTides.ControlSweep.controls(html, FormFields.handler_facts())

    assert Enum.sort(Enum.map(controls, & &1.id)) ==
             ["fleet-cancel-instruction-order", "route-cancel-instruction-order"]
  end
end
