defmodule TijaraTides.Domain.PortAdmissionTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.PortBerths

  test "a rejected queue head does not consume capacity and later tickets retain order" do
    port = %PortBerths{
      port: "Jakarta",
      capacity: 2,
      held: MapSet.new(["busy"]),
      waiting: Enum.map(["invalid", "first", "second"], &%{"id" => &1})
    }

    {next, decisions} =
      PortBerths.allocate(port, fn ship ->
        if ship["id"] == "invalid", do: :retry, else: :grant
      end)

    assert decisions == [{"invalid", :retry}, {"first", :grant}]
    assert next.held == MapSet.new(["busy", "first"])
    assert next.waiting == [%{"id" => "second"}]
    assert PortBerths.position(next, "second") == 1
    assert PortBerths.position(next, "first") == nil
  end

  test "a full port makes no eligibility probes or grants" do
    port = %PortBerths{
      port: "Jakarta",
      capacity: 1,
      held: MapSet.new(["busy"]),
      waiting: [%{"id" => "waiting"}]
    }

    {next, []} = PortBerths.allocate(port, fn _ -> flunk("full port must retain tickets") end)
    assert next.held == port.held
    assert next.waiting == port.waiting
    assert PortBerths.position(next, "waiting") == 1
  end

  test "generated eligibility combinations preserve FIFO among eligible tickets" do
    for mask <- 0..63, capacity <- 1..4, occupied <- 0..capacity do
      waiting = Enum.map(0..5, &%{"id" => to_string(&1)})

      eligible = fn row ->
        Bitwise.band(mask, Bitwise.bsl(1, String.to_integer(row["id"]))) != 0
      end

      held = MapSet.new(for n <- 1..occupied//1, do: "held:#{n}")
      port = %PortBerths{port: "Jakarta", capacity: capacity, held: held, waiting: waiting}

      {next, decisions} =
        PortBerths.allocate(port, fn row -> if eligible.(row), do: :grant, else: :retry end)

      expected =
        waiting |> Enum.filter(eligible) |> Enum.take(capacity - occupied) |> Enum.map(& &1["id"])

      assert for({id, :grant} <- decisions, do: id) == expected
      assert MapSet.size(next.held) <= capacity
      assert MapSet.subset?(held, next.held)
      assert length(Enum.uniq_by(decisions, &elem(&1, 0))) == length(decisions)
    end
  end

  test "immediate admission respects queue priority and cooldown without world access" do
    ship = %{"id" => "s", "status" => "docked"}
    assert PortBerths.available?([ship], ship, 10, 1)
    refute PortBerths.available?([ship], Map.put(ship, "berth_retry_ms", 11), 10, 1)
    queued = %{"id" => "queued", "status" => "docked", "berth_queued_ms" => 0}
    refute PortBerths.available?([ship, queued], ship, 10, 2)
    held = Map.put(ship, "berth_granted_ms", 0)
    assert PortBerths.available?([held, queued], held, 10, 1)
    refute PortBerths.available?([held, queued], queued, 10, 1)
  end

  test "world loaders agree, exclude sailing ships and include empty ports" do
    alias TijaraTides.Domain.PortBerthsWorld
    catalogue = %{"ports" => %{"p" => %{"berth_count" => 1}, "empty" => %{}}}

    fleet = [
      %{"id" => "later", "port" => "p", "status" => "docked", "berth_queued_ms" => 2},
      %{"id" => "first", "port" => "p", "status" => "docked", "berth_queued_ms" => 1},
      %{"id" => "away", "port" => "p", "status" => "sailing", "berth_granted_ms" => 0}
    ]

    state = %{clock_ms: 10, entities: %{"ships" => Map.new(fleet, &{&1["id"], &1})}}
    all = PortBerthsWorld.load_all(state, catalogue)
    assert all["p"] == PortBerthsWorld.load(state, "p", catalogue)
    assert all["p"].held == MapSet.new()
    assert Enum.map(all["p"].waiting, & &1["id"]) == ["first", "later"]
    assert all["empty"].waiting == []
    assert all["empty"].capacity == 4
  end

  test "the admission model has no world-reading dependency" do
    ast = File.read!("lib/tijara_tides/domain/port_berths.ex") |> Code.string_to_quoted!()

    Macro.prewalk(ast, fn
      {:__aliases__, _, parts} = node ->
        refute Enum.any?(parts, &(&1 in [:State, :ReadState, :PortBerthsWorld]))
        node

      node ->
        node
    end)

    Code.ensure_loaded!(PortBerths)
    refute function_exported?(PortBerths, :load, 3)
    refute function_exported?(PortBerths, :load_all, 2)
    refute function_exported?(PortBerths, :ships, 2)
  end
end
