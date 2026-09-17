defmodule TijaraTidesWeb.QueuedTradeTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias TijaraTidesWeb.GameUI.QueuedTrade

  test "queued sale identifies cargo, quantity, exact limit, berth state and cancellation" do
    ship = %{
      "id" => "ship",
      "name" => "Ore carrier",
      "port" => "Antwerp",
      "pending_side" => "sell",
      "pending_good" => "iron_ore",
      "pending_quantity" => 12,
      "pending_limit" => 12345,
      "berth_retry_ms" => 61000
    }

    public = %{
      "clock_ms" => 1000,
      "ships" => %{"ship" => %{"queue_position" => 2}},
      "berths" => %{"Antwerp" => %{"occupied" => 4, "capacity" => 4}}
    }

    html = render_component(&QueuedTrade.notice/1, id: "queued", ship: ship, public: public)
    assert html =~ "Ore carrier"
    assert html =~ "Sell 12 lots of Iron ore at no less than $123.45 per lot."
    assert html =~ "Berths in use: 4 / 4."
    assert html =~ "Queue position: 2"
    refute html =~ "Next admission attempt in"
    assert html =~ "phx-click=\"cancel-berth-trade\""
    assert html =~ "phx-value-id=\"ship\""

    buy =
      render_component(&QueuedTrade.notice/1,
        id: "queued",
        ship: %{ship | "pending_side" => "buy", "berth_retry_ms" => nil},
        public: public
      )

    blocked =
      render_component(&QueuedTrade.notice/1,
        id: "queued",
        ship: ship,
        public: public,
        reason: :buyer_budget
      )

    assert blocked =~ "Waiting for the buyer to afford the full order"
    refute blocked =~ "Waiting for berth admission"
    assert buy =~ "Buy 12 lots of Iron ore at no more than $123.45 per lot."
    refute buy =~ "Next admission attempt"
  end
end
