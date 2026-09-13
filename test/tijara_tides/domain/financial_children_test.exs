defmodule TijaraTides.Domain.FinancialChildrenTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.CompanyFinance.{OperatingBill, Guarantee}

  test "bill payment preserves identity and cannot overpay" do
    row = %{"id" => "bill", "company_id" => "c", "due_ms" => 12, "remaining" => 80}
    bill = OperatingBill.from_row(row)
    assert OperatingBill.to_row(bill) == row
    assert OperatingBill.pay(bill, 30) == %{bill | remaining: 50}
    assert_raise ArgumentError, fn -> OperatingBill.pay(bill, 81) end
    assert_raise ArgumentError, fn -> OperatingBill.from_row(Map.put(row, "extra", 1)) end
  end

  test "guarantee settlement is bounded by escrow and cannot settle twice" do
    row = %{
      "id" => "g",
      "company_id" => "c",
      "sponsor_id" => "s",
      "beneficiary_id" => "b",
      "borrower_company_id" => nil,
      "amount" => 100,
      "forfeited" => 0,
      "status" => "pledged",
      "created_ms" => 0
    }

    pledge = Guarantee.from_row(row)
    assert Guarantee.to_row(pledge) == row
    closed = Guarantee.settle(pledge, 30)
    assert closed.status == "claimed"
    assert closed.forfeited == 30
    assert_raise ArgumentError, fn -> Guarantee.settle(closed, 30) end
    assert_raise ArgumentError, fn -> Guarantee.settle(pledge, 101) end
    assert_raise KeyError, fn -> Guarantee.from_row(Map.delete(row, "beneficiary_id")) end
    assert_raise ArgumentError, fn -> Guarantee.from_row(Map.put(row, "extra", 1)) end
  end
end
