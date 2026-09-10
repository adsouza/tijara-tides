defmodule TijaraTides.Domain.ReportingTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.Reporting
  @quarter 7 * 86_400_000

  defp fixture(clock \\ 0, cash \\ 10_000) do
    %{
      clock_ms: clock,
      entities: %{
        "companies" => %{
          "c" => %{
            "id" => "c",
            "name" => "Trading",
            "account_id" => "a",
            "cash" => cash,
            "created_ms" => clock,
            "bankruptcy_ms" => nil
          }
        },
        "accounts" => %{"a" => %{"id" => "a", "bankruptcies" => 2}}
      }
    }
    |> Reporting.initialize()
  end

  defp reports(state) do
    state = Reporting.advance(state)

    state.entities["financial_reports"]
    |> Map.values()
    |> Enum.map(fn row ->
      company = state.entities["companies"][row["company_id"]]

      row
      |> Map.merge(%{
        "name" => company["name"],
        "bankruptcy_ms" => company["bankruptcy_ms"],
        "bankruptcies" => 2
      })
      |> TijaraTides.UseCases.ReportQueries.decorate(state.clock_ms)
    end)
  end

  defp quarter(state, index \\ 0),
    do:
      Enum.find(
        reports(state),
        &(&1["period"] == "quarter" and &1["period_index"] == index)
      )

  test "borrowing adds time-weighted capital without creating profit" do
    state = fixture()

    state =
      Reporting.post(%{state | clock_ms: div(@quarter, 2)}, "c", [
        {"cash_available", 10_000},
        {"loan_principal", -10_000}
      ])

    row = quarter(%{state | clock_ms: @quarter})
    assert row["average_capital"] == 15_000
    assert row["profit"] == 0
    assert row["roi"] == 0.0
    assert row["eligible"]
    assert row["bankruptcies"] == 2
  end

  test "revenue and every cost category reconcile to net profit; asset transfers are neutral" do
    state = fixture()
    state = Reporting.post(state, "c", [{"cash_available", -4000}, {"inventory", 4000}])

    state =
      Reporting.post(state, "c", [
        {"cash_available", 7000},
        {"sales_revenue", -7000},
        {"inventory", -4000},
        {"cost_of_goods", 4000}
      ])

    state = Reporting.post(state, "c", [{"cash_available", -200}, {"interest_expense", 200}])
    state = Reporting.post(state, "c", [{"fleet", -300}, {"depreciation_expense", 300}])
    row = quarter(%{state | clock_ms: @quarter})
    assert row["revenue"] == 7000
    assert row["cargo_cost"] == 4000
    assert row["operating"] == 200
    assert row["depreciation"] == 300
    assert row["profit"] == 2500
    assert row["average_capital"] == 12500
    assert row["roi"] == 20.0
  end

  test "events exactly at a boundary belong to the new period" do
    state =
      Reporting.post(%{fixture() | clock_ms: @quarter}, "c", [
        {"sales_revenue", -1000},
        {"cash_available", 1000}
      ])

    assert quarter(state)["profit"] == 0
    assert quarter(state)["eligible"]
    assert quarter(state, 1)["profit"] == 1000
    refute quarter(state, 1)["eligible"]
  end

  test "mid-period starts are unranked, later complete periods eligible, and years require all four quarters" do
    state = fixture(div(@quarter, 2))
    rows = reports(%{state | clock_ms: @quarter * 4})
    refute Enum.find(rows, &(&1["period"] == "quarter" and &1["period_index"] == 0))["eligible"]
    assert Enum.find(rows, &(&1["period"] == "quarter" and &1["period_index"] == 1))["eligible"]
    refute Enum.find(rows, &(&1["period"] == "year" and &1["period_index"] == 0))["eligible"]
  end

  test "zero capital has no ROI; restart does not reinitialize accumulated reports" do
    state = fixture(0, 0)
    state = Reporting.advance(%{state | clock_ms: @quarter})
    assert Reporting.initialize(state) == state
    assert quarter(state)["roi"] == nil
    assert quarter(state)["average_capital"] == 0
    assert Reporting.advance(state) == state
  end

  test "bankruptcy preserves history but disqualifies the incomplete final period" do
    state = fixture()
    state = put_in(state, [:entities, "companies", "c", "bankruptcy_ms"], div(@quarter, 2))
    refute quarter(%{state | clock_ms: @quarter})["eligible"]
    row = quarter(%{state | clock_ms: @quarter})
    refute Map.has_key?(TijaraTides.UseCases.ReportQueries.public_row(row), "capital_ms")
  end
end
