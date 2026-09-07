defmodule TijaraTidesWeb.DepartureErrorsTest do
  use ExUnit.Case, async: true
  alias TijaraTidesWeb.GameLive

  test "funding message explains fuel, canal fees, spendable cash and shortfall" do
    message = GameLive.error_message({:departure_funds, 10_000, 25_000, 20_000})
    assert message =~ "$350.00"
    assert message =~ "$100.00 for fuel"
    assert message =~ "$250.00 in canal fees"
    assert message =~ "$200.00 available after reservations"
    assert message =~ "shortfall of $150.00"
  end

  test "handling and arrears messages explain the next action" do
    assert GameLive.error_message({:departure_busy, "loading", 1500}) =~ "still loading cargo"
    assert GameLive.error_message({:departure_busy, "unloading", 1500}) =~ "about 2 seconds"
    assert GameLive.error_message({:departure_unpaid, 1250}) =~ "$12.50 in unpaid operating costs"
    assert GameLive.error_message({:departure_fuel_limit, 2000, 1000}) =~ "confirm again"
  end
end
