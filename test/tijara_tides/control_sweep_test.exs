defmodule TijaraTides.ControlSweepTest do
  use ExUnit.Case, async: false
  alias TijaraTides.ControlSweep

  @facts %{
    "command" => %{command?: true, actions: MapSet.new(["sail", "reroute"])},
    "single" => %{command?: true, actions: MapSet.new(["rename"])},
    "empty" => %{command?: true, actions: MapSet.new()},
    "selection" => %{command?: false, actions: MapSet.new()}
  }

  test "named submit buttons keep distinct actions, operations and disabled state" do
    html = """
    <form id="route" phx-submit="command">
      <input name="action" value="route">
      <input name="operation" value="remove">
      <button name="action" value="save">Save</button>
      <button name="action" value="cancel">Cancel</button>
      <button name="action" value="delete" disabled>Delete</button>
    </form>
    """

    assert Enum.map(ControlSweep.controls(html, @facts), &{&1.key, &1.submitter, &1.id}) == [
             {{"command", "save", "remove"}, %{"action" => "save"}, "route"},
             {{"command", "cancel", "remove"}, %{"action" => "cancel"}, "route"}
           ]
  end

  test "hidden values are deduplicated and multiple candidates are sorted" do
    html = """
    <form phx-submit="command">
      <input name="action" value="route"><input name="action" value="route">
      <input name="operation" value="update"><input name="operation" value="add">
      <button>Submit</button>
    </form>
    <form phx-submit="command"><button>Fallback</button></form>
    <form phx-submit="empty"></form>
    """

    assert Enum.map(ControlSweep.controls(html, @facts), & &1.key) == [
             {"command", "route", ["add", "update"]},
             {"command", ["reroute", "sail"], nil},
             {"empty", nil, nil}
           ]
  end

  test "forms with an enabled unnamed submitter survive while disabled-only forms do not" do
    html = """
    <form id="disabled" phx-submit="single"><button disabled>Submit</button></form>
    <form id="mixed" phx-submit="single">
      <button disabled>Submit</button><button>Submit</button>
    </form>
    <form id="implicit" phx-submit="single"><button type="button" disabled>Other</button></form>
    <form phx-submit="selection"><button>Selection</button></form>
    <form phx-submit="unknown"><button>Unknown</button></form>
    """

    assert Enum.map(ControlSweep.controls(html, @facts), & &1.id) == ["mixed", "implicit"]
  end

  test "clicks retain every rendered value and ignore disabled, unknown and JS controls" do
    html = """
    <button id="remove" phx-click="command" phx-value-action="route"
      phx-value-operation="remove" phx-value-ship="ship:1">Remove</button>
    <button id="rename" phx-click="single">Rename</button>
    <button phx-click="single" disabled>Disabled</button>
    <button phx-click="selection">Select</button>
    <button phx-click="unknown">Unknown</button>
    <button phx-click='[["push", {}]]'>JS</button>
    """

    assert [remove, rename] = ControlSweep.controls(html, @facts)
    assert remove.kind == :click
    assert remove.key == {"command", "route", "remove"}
    assert remove.values == %{"action" => "route", "operation" => "remove", "ship" => "ship:1"}
    assert rename.key == {"single", "rename", nil}
    assert rename.values == %{}
  end

  test "outcomes retain command order and reasons while ignoring non-command operations" do
    assert ControlSweep.outcomes(fn ->
             emit(%{operation: :query, outcome: :ok})
             emit(%{operation: :command, outcome: :committed})
             emit(%{operation: :command, outcome: :rejected, reason: :not_owner})
             :result
           end) == {:result, [{:committed, nil}, {:rejected, :not_owner}]}

    assert ControlSweep.outcomes(fn -> :no_command end) == {:no_command, []}
  end

  test "telemetry handlers are detached even when the submitted operation raises" do
    before = :telemetry.list_handlers([:tijara_tides, :operation, :stop])

    assert_raise RuntimeError, "failed submission", fn ->
      ControlSweep.outcomes(fn -> raise "failed submission" end)
    end

    assert :telemetry.list_handlers([:tijara_tides, :operation, :stop]) == before
  end

  defp emit(metadata),
    do:
      :telemetry.execute(
        [:tijara_tides, :operation, :stop],
        %{duration: 0},
        Map.put(metadata, :correlation_id, "control-sweep-test")
      )
end
