defmodule TijaraTidesWeb.DepartureWaitTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias TijaraTidesWeb.GameUI.{DepartureWait, QueuedDeparture}

  @ship %{"id" => "ship", "port" => "Antwerp", "status" => "docked"}
  @plan %{
    "port" => "Antwerp",
    "onward" => "Mumbai",
    "auto_depart" => true,
    "departure_wait" => "Waiting for cargo orders to be filled or cancelled"
  }
  @order %{
    "id" => "seafood-order",
    "ship_id" => "ship",
    "port" => "Antwerp",
    "side" => "sell",
    "good" => "seafood",
    "quantity" => 67,
    "filled" => 63,
    "status" => "waiting",
    "reason" => "Waiting for cargo aboard"
  }

  test "queued departure exposes the actual partial-fill blocker" do
    html =
      render_component(&QueuedDeparture.panel/1,
        ship: @ship,
        private: %{
          "visit_plans" => %{"ship|Antwerp" => @plan},
          "ship_instructions" => %{"seafood-order" => @order}
        },
        destination: "Mumbai",
        request_id: "request"
      )

    assert html =~ "sell Seafood at Antwerp, 4 lots unfilled (63/67 filled)"
    assert html =~ "Waiting for cargo aboard"
    assert html =~ "Fill or cancel the remaining cargo orders to depart."
    refute html =~ "Waiting for cargo orders to be filled or cancelled"
  end

  test "every current visit blocker is shown; other ships, ports and closed orders are omitted" do
    orders = [
      @order,
      %{@order | "id" => "planned", "status" => "planned", "reason" => "Waiting for a berth"},
      %{@order | "id" => "other-ship", "ship_id" => "other", "reason" => "OTHER_SHIP"},
      %{@order | "id" => "next-port", "port" => "Mumbai", "reason" => "NEXT_PORT"},
      %{@order | "id" => "filled", "status" => "filled", "reason" => "FILLED_ORDER"},
      %{@order | "id" => "cancelled", "status" => "cancelled", "reason" => "CANCELLED_ORDER"}
    ]

    html = render_component(&DepartureWait.notice/1, ship: @ship, plan: @plan, orders: orders)
    assert html =~ "Waiting for cargo aboard"
    assert html =~ "Waiting for a berth"
    assert Enum.count(LazyHTML.query(LazyHTML.from_fragment(html), "div.mt-1")) == 2

    for hidden <- ~w(OTHER_SHIP NEXT_PORT FILLED_ORDER CANCELLED_ORDER),
        do: refute(html =~ hidden)
  end

  test "other departure reasons and queued manual trades retain their warning" do
    reason = "Waiting for cargo handling to finish"

    html =
      render_component(&DepartureWait.notice/1,
        ship: @ship,
        plan: %{@plan | "departure_wait" => reason},
        orders: [@order]
      )

    assert html =~ reason
    refute html =~ "Seafood"

    html = render_component(&DepartureWait.notice/1, ship: @ship, plan: @plan)
    assert html =~ @plan["departure_wait"]

    for plan <- [nil, %{@plan | "departure_wait" => nil}] do
      assert render_component(&DepartureWait.notice/1, ship: @ship, plan: plan, orders: [@order]) ==
               ""
    end
  end

  test "Arabic translates the blocker, cargo, port and recovery guidance" do
    html =
      TijaraTides.Localization.with_locale("ar", fn ->
        render_component(&DepartureWait.notice/1, ship: @ship, plan: @plan, orders: [@order])
      end)

    assert html =~ "٤"
    assert html =~ "٦٣/٦٧"
    assert html =~ "بانتظار وجود بضائع على متن السفينة"
    refute html =~ "Departure blocked"
    refute html =~ "Seafood"
    refute html =~ "Antwerp"
    refute html =~ "Fill or cancel"
  end
end
