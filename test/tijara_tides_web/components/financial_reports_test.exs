defmodule TijaraTidesWeb.FinancialReportsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias TijaraTidesWeb.FinancialReports

  test "renders the supplied page without reordering it or deciding eligibility" do
    row = %{"name" => "Company", "profit" => 1200, "roi" => 5.0, "bankruptcies" => 2}

    data = %{
      period: "quarter",
      metric: "profit",
      selected: 2,
      current: 3,
      minimum: 0,
      ranked: [row],
      provisional: [],
      own: [],
      page: 1,
      limit: 10,
      ranked_count: 60,
      provisional_count: 0,
      own_count: 0
    }

    html = render_component(&FinancialReports.panel/1, data: data, open: true)
    assert html =~ "Company"
    assert html =~ "11"
    assert html =~ "Page 2"
    assert html =~ "Completed"
    assert html =~ ~s(<select name="period_number")
    refute html =~ ~s(type="number")
    assert html =~ "Quarter 4 (current)"
    assert html =~ "Previous page"

    own_html =
      render_component(&FinancialReports.panel/1,
        data: Map.merge(data, %{own_count: 21, own_page: 1}),
        open: true
      )

    assert own_html =~ "Your companies · page 2"
    assert own_html =~ "report-own-page"
    assert own_html =~ "Next companies"
  end

  test "closed panel contains no results, and query errors have a retry action" do
    html = render_component(&FinancialReports.panel/1)
    refute html =~ "Company results &amp; leaderboards"
    html = render_component(&FinancialReports.panel/1, open: true, error: :unavailable)
    assert html =~ "temporarily unavailable"
    assert html =~ "Retry"
  end
end
