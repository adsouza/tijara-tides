defmodule TijaraTidesWeb.ShipBerthTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias TijaraTidesWeb.GameUI.ShipBerth

  test "scene passes committed timing without cargo or instruction payloads" do
    ship = %{
      "id" => "ship:1",
      "port" => "Singapore",
      "status" => "loading",
      "arrive_ms" => 180_000,
      "handling_started_ms" => 100_000,
      "handling_volume_l" => 450_000,
      "cargo" => [%{"good" => "PRIVATE_CARGO", "quantity" => 9182}],
      "pending_good" => "PRIVATE_ORDER"
    }

    html =
      render_component(&ShipBerth.scene/1,
        ship: ship,
        clock: 120_000,
        queue_position: 2,
        cargo_volume_l: 675_000,
        capacity_l: 900_000
      )

    assert html =~ ~s(data-clock="120000")
    assert html =~ ~s(data-complete="180000")
    assert html =~ ~s(data-start="100000")
    assert html =~ ~s(data-volume="450000")
    assert html =~ ~s(data-cargo-volume="675000")
    assert html =~ ~s(data-capacity="900000")
    assert html =~ ~s(data-queued="true")
    assert html =~ ~s(data-laden="true")
    assert html =~ "Waiting for a berth"
    assert html =~ ~s(phx-update="ignore")
    refute html =~ "PRIVATE_CARGO"
    refute html =~ "PRIVATE_ORDER"
    refute html =~ "9182"
  end

  test "Arabic berth labels translate and timing stays machine readable" do
    html =
      TijaraTides.Localization.with_locale("ar", fn ->
        render_component(&ShipBerth.scene/1,
          ship: %{"id" => "tanker", "port" => "Singapore", "status" => "unloading"},
          clock: 1000,
          liquid: true
        )
      end)

    assert html =~ "مشهد الرصيف"
    assert html =~ "إيقاف الحركة مؤقتًا"
    assert html =~ "استئناف الحركة"
    assert html =~ ~s(data-clock="1000")
    assert html =~ ~s(data-liquid="true")
    assert html =~ ~s(data-laden="false")
  end
end
