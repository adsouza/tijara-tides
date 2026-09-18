defmodule TijaraTides.Domain.LoanActionsTest do
  alias TijaraTides.Domain.CompanyFinance
  use ExUnit.Case, async: true

  defp company,
    do: %CompanyFinance{id: "c", cash: 20_000, reserved: 1000, unpaid: 0, profit: 0}

  defp loan do
    {:ok, finance, _, _} =
      CompanyFinance.loan_transition(
        %{company() | account_id: "a"},
        "a",
        {:borrow, 10_000, "loan", %{suspended: false, available: 10_000, rate_bps: 800}},
        0
      )

    %{hd(finance.loans) | interest_accrued: 123}
  end

  test "repayment uses exact payoff while recast preserves interest plus a dollar of principal" do
    actions = CompanyFinance.loan_actions(company(), loan())
    assert actions["payoff"] == 10_123
    assert actions["repay_enabled"]
    assert actions["recast_min"] == 223
    assert actions["recast_max"] == 10_123
    assert actions["recast_enabled"]

    assert CompanyFinance.loan_actions(%{company() | cash: 11_122}, loan())[
             "repay_enabled"
           ] ==
             false

    assert CompanyFinance.loan_actions(%{company() | cash: 11_123}, loan())[
             "repay_enabled"
           ]
  end

  test "repayment includes overdue and accrued interest at the available-cash boundary" do
    overdue = %{loan() | interest_due: 277, principal_due: 500}

    for {available, enabled?} <- [{10_399, false}, {10_400, true}, {10_401, true}] do
      actions = CompanyFinance.loan_actions(%{company() | cash: available + 1000}, overdue)

      # The overdue principal is already part of the remaining balance.
      assert actions["payoff"] == 10_400
      assert actions["repay_enabled"] == enabled?
      refute actions["recast_allowed"]
      refute actions["recast_enabled"]
    end
  end

  test "cash reservations and arrears consistently bound eligibility" do
    for free <- [222, 223, 224] do
      actions = CompanyFinance.loan_actions(%{company() | cash: free + 1000}, loan())
      assert actions["recast_max"] == free
      assert actions["recast_enabled"] == free >= 223
    end

    for blocked <- [
          %{loan() | principal_due: 1},
          %{loan() | interest_due: 1},
          %{loan() | periods_left: 0},
          %{loan() | status: "repaid"}
        ] do
      refute CompanyFinance.loan_actions(company(), blocked)["recast_allowed"]
    end

    refute CompanyFinance.loan_actions(%{company() | unpaid: 1}, loan())[
             "recast_allowed"
           ]

    refute CompanyFinance.loan_actions(%{company() | bankruptcy_ms: 0}, loan())[
             "repay_enabled"
           ]
  end
end
