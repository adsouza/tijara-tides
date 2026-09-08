defmodule TijaraTidesWeb.DepartureErrorsTest do
  use ExUnit.Case, async: true
  alias TijaraTidesWeb.GameLive

  test "funding message explains fuel, canal fees, spendable cash and shortfall" do
    message = GameLive.error_message({:departure_funds, 10_000, 25_000, 20_000})
    assert message =~ "$350"
    assert message =~ "$100 for fuel"
    assert message =~ "$250 in canal fees"
    assert message =~ "$200 available after reservations"
    assert message =~ "shortfall of $150"
  end

  test "the stated shortfall is never less than the cash actually missing" do
    # $350.00 required against $199.51 available: the true shortfall is $150.49.
    message = GameLive.error_message({:departure_funds, 10_000, 25_000, 19_951})

    assert message =~ "shortfall of $151"
    refute message =~ "shortfall of $150"
  end

  test "the funding message's own arithmetic agrees with the shortfall it states" do
    for available <- [0, 1, 49, 50, 99, 19_951, 34_999, 35_000] do
      message = GameLive.error_message({:departure_funds, 10_000, 25_000, available})
      [required] = Regex.run(~r/requires \$(\d+)/, message, capture: :all_but_first)
      [have] = Regex.run(~r/\$(\d+) available/, message, capture: :all_but_first)
      [short] = Regex.run(~r/shortfall of \$(\d+)/, message, capture: :all_but_first)

      assert String.to_integer(required) - String.to_integer(have) ==
               String.to_integer(short),
             "displayed figures disagree for available=#{available}: #{message}"

      assert String.to_integer(short) * 100 >= 35_000 - available,
             "stated shortfall understates the cash needed for available=#{available}"
    end
  end

  test "the stated fuel and canal costs add up to the stated total" do
    for fuel <- [10_000, 10_001, 10_049, 10_050, 10_099] do
      message = GameLive.error_message({:departure_funds, fuel, 25_000, 0})
      [total] = Regex.run(~r/requires \$(\d+)/, message, capture: :all_but_first)
      [f] = Regex.run(~r/\$(\d+) for fuel/, message, capture: :all_but_first)
      [c] = Regex.run(~r/\$(\d+) in canal/, message, capture: :all_but_first)

      assert String.to_integer(f) + String.to_integer(c) == String.to_integer(total),
             "breakdown does not sum to the total for fuel=#{fuel}: #{message}"

      assert String.to_integer(total) * 100 >= fuel + 25_000,
             "stated total understates the cost for fuel=#{fuel}"
    end
  end

  test "handling and arrears messages explain the next action" do
    assert GameLive.error_message({:departure_busy, "loading", 1500}) =~ "still loading cargo"
    assert GameLive.error_message({:departure_busy, "unloading", 1500}) =~ "about 2 seconds"
    assert GameLive.error_message({:departure_unpaid, 1250}) =~ "$13 in unpaid operating costs"
    assert GameLive.error_message({:departure_fuel_limit, 2000, 1000}) =~ "confirm again"
  end
end
