defmodule TijaraTidesWeb.PortTrafficTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias TijaraTidesWeb.PortTraffic

  test "status and company totals count present ships, including queued ships, but never voyages" do
    ship = fn id, owner, port, status ->
      {id, %{"id" => id, "name" => id, "company_id" => owner, "port" => port, "status" => status}}
    end

    public = %{
      "companies" => %{"a" => %{"name" => "Alpha"}, "b" => %{"name" => "Beta"}},
      "ships" =>
        Map.new([
          ship.("One", "a", "Singapore", "docked"),
          ship.("Two", "a", "Singapore", "loading"),
          ship.("Three", "b", "Singapore", "queued"),
          ship.("Four", "b", "Singapore", "unloading"),
          ship.("Departed", "a", "Singapore", "sailing"),
          ship.("Elsewhere", "b", "Jakarta", "docked")
        ])
    }

    status = render_component(&PortTraffic.traffic/1, public: public, port: "Singapore")
    assert status =~ "Port traffic · 4 ships"

    for label <- ["Berthed", "Loading", "Queued", "Unloading"],
        do: assert(status =~ "#{label} · 1 ship")

    refute status =~ "Departed"
    refute status =~ "Elsewhere"

    companies =
      render_component(&PortTraffic.traffic/1,
        public: public,
        port: "Singapore",
        grouping: "company"
      )

    assert companies =~ "Alpha · 2 ships"
    assert companies =~ "Beta · 2 ships"
    assert companies =~ "Three"
    empty = render_component(&PortTraffic.traffic/1, public: public, port: "Tokyo")
    assert empty =~ "Port traffic · 0 ships"
    assert empty =~ "No ships at this port."
  end
end
