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
  end

  test "a full port makes no eligibility probes or grants" do
    port = %PortBerths{
      port: "Jakarta",
      capacity: 1,
      held: MapSet.new(["busy"]),
      waiting: [%{"id" => "waiting"}]
    }

    assert PortBerths.allocate(port, fn _ -> flunk("full port must retain tickets") end) ==
             {port, []}
  end
end
