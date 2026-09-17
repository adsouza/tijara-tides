defmodule TijaraTidesWeb.QueuedDepartureTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias TijaraTidesWeb.GameUI.QueuedDeparture

  test "handling offers a persisted departure and exposes its destination and cancellation" do
    ship = %{"id" => "ship", "port" => "Jakarta", "status" => "loading"}
    args = [ship: ship, private: %{}, destination: "Singapore", request_id: "request"]
    html = render_component(&QueuedDeparture.panel/1, args)
    assert html =~ "Sail to Singapore after handling"
    assert html =~ ~s(name="auto_depart" value="true")
    plan = %{"auto_depart" => true, "onward" => "Singapore", "departure_wait" => nil}
    queued = Keyword.put(args, :private, %{"visit_plans" => %{"ship|Jakarta" => plan}})
    html = render_component(&QueuedDeparture.panel/1, queued)
    assert html =~ "Queued departure to Singapore"
    assert html =~ "Cancel queued departure"
    assert html =~ ~s(name="auto_depart" value="false")
    refute html =~ ~s(id="queue-departure")

    html =
      render_component(&QueuedDeparture.panel/1, Keyword.put(queued, :destination, "Colombo"))

    assert html =~ "Queued departure to Singapore"
    assert html =~ "Sail to Colombo after handling"

    assert render_component(&QueuedDeparture.panel/1, Keyword.put(args, :destination, nil)) =~
             ~s(id="queued-departure")

    refute render_component(&QueuedDeparture.panel/1, Keyword.put(args, :destination, nil)) =~
             ~s(id="queue-departure")
  end
end
