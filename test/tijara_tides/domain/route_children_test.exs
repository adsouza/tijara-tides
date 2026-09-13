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
         "reason" => "Following route"
       }},
      {RouteStop,
       %{
         "id" => "stop",
         "ship_id" => "s",
         "company_id" => "c",
         "position" => 1,
         "port" => "Jakarta"
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
         "budget" => nil
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
  end
end
