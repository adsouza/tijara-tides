defmodule TijaraTides.Domain.LoanActionsTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.CompanyFinance

  defp company, do: %{"cash" => 20_000, "reserved" => 1000, "unpaid" => 0, "bankruptcy_ms" => nil}

  defp loan,
    do: %{
      "status" => "open",
      "remaining" => 10_000,
      "interest_accrued" => 123,
      "interest_due" => 0,
      "principal_due" => 0,
      "periods_left" => 4
    }

  test "repayment uses exact payoff while recast preserves interest plus a dollar of principal" do
    actions = CompanyFinance.loan_actions(company(), loan())
    assert actions["payoff"] == 10_123
    assert actions["repay_enabled"]
    assert actions["recast_min"] == 223
    assert actions["recast_max"] == 10_123
    assert actions["recast_enabled"]

    assert CompanyFinance.loan_actions(%{company() | "cash" => 11_122}, loan())["repay_enabled"] ==
             false

    assert CompanyFinance.loan_actions(%{company() | "cash" => 11_123}, loan())["repay_enabled"]
  end

  test "cash reservations and arrears consistently bound eligibility" do
    for free <- [222, 223, 224] do
      actions = CompanyFinance.loan_actions(%{company() | "cash" => free + 1000}, loan())
      assert actions["recast_max"] == free
      assert actions["recast_enabled"] == free >= 223
    end

    for blocked <- [
          %{loan() | "principal_due" => 1},
          %{loan() | "interest_due" => 1},
          %{loan() | "periods_left" => 0},
          %{loan() | "status" => "repaid"}
        ] do
      refute CompanyFinance.loan_actions(company(), blocked)["recast_allowed"]
    end

    refute CompanyFinance.loan_actions(%{company() | "unpaid" => 1}, loan())["recast_allowed"]

    refute CompanyFinance.loan_actions(%{company() | "bankruptcy_ms" => 0}, loan())[
             "repay_enabled"
           ]
  end
end
