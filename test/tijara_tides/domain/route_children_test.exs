defmodule TijaraTides.Domain.RouteChildrenTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.Ship.{RouteHeader, RouteStop, RouteTarget, VisitPlan}

  test "route children round trip every persisted field and reject unrecognized fields" do
    rows = [
      {RouteHeader,
       %{
         "id" => "s",
         "ship_id" => "s",
         "company_id" => "c",
         "status" => "running",
         "cursor" => 1,
         "visit" => 4,
         "phase" => "buying",
         "auto_depart" => true,
         "stop_after" => false,
         "reason" => "Following route",
         "visit_arrived_ms" => 100,
         "wait_deadline_ms" => 1000,
         "wait_timed_out" => false
       }},
      {RouteStop,
       %{
         "id" => "stop",
         "ship_id" => "s",
         "company_id" => "c",
         "position" => 1,
         "port" => "Jakarta",
         "max_wait_ms" => 900
       }},
      {RouteTarget,
       %{
         "id" => "target",
         "ship_id" => "s",
         "company_id" => "c",
         "stop_id" => "stop",
         "side" => "buy",
         "good" => "lumber",
         "quantity_mode" => "maximum",
         "quantity" => nil,
         "limit" => 100,
         "budget" => nil,
         "min_remaining_ms" => 120_000
       }},
      {VisitPlan,
       %{
         "id" => "visit",
         "ship_id" => "s",
         "company_id" => "c",
         "port" => "Jakarta",
         "onward" => "Singapore",
         "auto_depart" => true,
         "departure_wait" => nil
       }}
    ]

    for {module, row} <- rows do
      assert module.to_row(module.from_row(row)) == row
      assert_raise ArgumentError, fn -> module.from_row(Map.put(row, "unmapped", 1)) end
      assert_raise KeyError, fn -> module.from_row(Map.delete(row, "ship_id")) end
    end

    {_, route} = hd(rows)
    assert_raise ArgumentError, fn -> RouteHeader.from_row(%{route | "phase" => "sailing"}) end
    assert_raise ArgumentError, fn -> RouteHeader.from_row(%{route | "cursor" => -1}) end
    legacy = Map.drop(route, ~w(visit_arrived_ms wait_deadline_ms wait_timed_out))
    assert RouteHeader.from_row(legacy).wait_deadline_ms == nil
    refute RouteHeader.from_row(legacy).wait_timed_out

    for changes <- [
          %{"visit_arrived_ms" => -1},
          %{"visit_arrived_ms" => "100"},
          %{"wait_deadline_ms" => 100},
          %{"wait_deadline_ms" => 99},
          %{"visit_arrived_ms" => nil},
          %{"wait_deadline_ms" => "1000"},
          %{"wait_timed_out" => nil}
        ] do
      assert_raise ArgumentError, fn -> RouteHeader.from_row(Map.merge(route, changes)) end
    end

    {_, stop} = Enum.at(rows, 1)
    assert RouteStop.from_row(Map.delete(stop, "max_wait_ms")).max_wait_ms == nil

    for wait <- [1, RouteStop.max_wait_ms(), nil] do
      assert RouteStop.from_row(Map.put(stop, "max_wait_ms", wait)).max_wait_ms == wait
    end

    for wait <- [0, -1, RouteStop.max_wait_ms() + 1, "1", 1.5] do
      assert_raise ArgumentError, fn -> RouteStop.from_row(Map.put(stop, "max_wait_ms", wait)) end
    end

    {_, target} = Enum.at(rows, 2)
    assert RouteTarget.from_row(Map.delete(target, "min_remaining_ms")).min_remaining_ms == 0

    for minimum <- [nil, false, -1, 2_592_000_001, "60", 1.5] do
      assert_raise ArgumentError, fn ->
        RouteTarget.from_row(Map.put(target, "min_remaining_ms", minimum))
      end
    end

    assert_raise ArgumentError, fn -> RouteTarget.from_row(Map.put(target, "side", "sell")) end
  end
end
