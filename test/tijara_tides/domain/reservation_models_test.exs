defmodule TijaraTides.Domain.ReservationModelsTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{VisitBudget, DepartureRequest, LiquidationPool, Warehouse}

  defp spec do
    %{
      id: "visit",
      company_id: "company",
      ship_id: "ship",
      stop_id: "stop",
      port: "Jakarta",
      configured: 100,
      visit: 2
    }
  end

  defp pool do
    w = %Warehouse{
      id: "warehouse",
      company_id: "company",
      port: "Jakarta",
      storage: "dry",
      good: nil,
      blocks: 3,
      started_ms: 0,
      expires_ms: 17,
      rent: 7,
      prepaid: 0,
      protected_ms: 0,
      grace_ms: 11,
      surcharge_bps: 2500
    }

    LiquidationPool.new(w, 2, 3)
  end

  test "spent visit funds cannot be refunded by shrinking the reservation" do
    budget = VisitBudget.new(spec(), 100, false) |> VisitBudget.consume(60)
    assert {:error, :visit_budget_committed} = VisitBudget.resize(budget, 59, 1000, 0)
    assert {:ok, reduced, -40} = VisitBudget.resize(budget, 60, 0, 9)
    assert reduced.remaining == 0
    assert VisitBudget.Rows.decode(VisitBudget.Rows.encode(reduced)) == reduced
    assert_raise ArgumentError, fn -> VisitBudget.consume(reduced, 1) end
    assert {:error, :insufficient_cash} = VisitBudget.resize(reduced, 70, 9, 0)
  end

  test "accumulation keeps its first deadline and release preserves accepted request terms" do
    request = DepartureRequest.new(spec(), "wait", 100, 10)
    held = request |> DepartureRequest.accumulate(30, 20) |> DepartureRequest.accumulate(70, 50)
    assert held.window_deadline_ms == 20
    assert held.accumulated == 100
    assert_raise ArgumentError, fn -> DepartureRequest.accumulate(held, 1, 50) end
    released = DepartureRequest.release(held, 80)
    assert released.accumulated == 0 and released.window_deadline_ms == nil
    assert released.cooldown_ms == 80 and released.blocked_ms == 10
    assert released.required == 100 and released.visit == 2
    assert DepartureRequest.Rows.decode(DepartureRequest.Rows.encode(released)) == released
  end

  test "rent and mixed-denominator clearance retain exact remainders through row round trips" do
    whole = LiquidationPool.accrue(pool(), 41)

    split =
      Enum.reduce(18..41, pool(), fn now, p ->
        p
        |> LiquidationPool.accrue(now)
        |> LiquidationPool.Rows.encode()
        |> LiquidationPool.Rows.decode()
      end)

    assert split == whole
    {split, first} = LiquidationPool.clearance_value(split, "fruit", 1, 3)
    split = split |> LiquidationPool.Rows.encode() |> LiquidationPool.Rows.decode()
    {split, second} = LiquidationPool.clearance_value(split, "fruit", 3, 4)
    assert first + second == 1
    assert split.clearance_remainders["fruit"] == %{"numerator" => 1, "denominator" => 12}
  end

  test "liquidation completion conserves proceeds and seals economic transitions" do
    p = pool()
    assert_raise ArgumentError, fn -> LiquidationPool.begin(p, p.grace_end_ms - 1) end

    closed =
      p
      |> LiquidationPool.begin(p.grace_end_ms)
      |> LiquidationPool.sale(100, 2)
      |> LiquidationPool.complete(10, 90, false, 40)

    assert closed.charged + closed.paid + closed.sunk == closed.proceeds
    assert LiquidationPool.accrue(closed, 1000) == closed
    assert_raise ArgumentError, fn -> LiquidationPool.sale(closed, 1, 0) end
    assert_raise ArgumentError, fn -> LiquidationPool.occupancy(closed, 1) end
  end
end
