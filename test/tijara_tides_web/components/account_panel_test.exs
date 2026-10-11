defmodule TijaraTidesWeb.AccountPanelTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias TijaraTides.Localization
  alias TijaraTidesWeb.GameUI.AccountPanel

  defp render_forecast(status, remaining \\ 172_800_000, refund \\ nil, period \\ 172_800_000) do
    render_component(&AccountPanel.expectation/1,
      forecast: %{
        "status" => status,
        "remaining_ms" => remaining,
        "refund_ms" => refund,
        "period_ms" => period
      }
    )
  end

  defp countdown(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#invitation-countdown")
    |> LazyHTML.text()
    |> String.trim()
  end

  test "an unavailable forecast renders without a countdown" do
    html = render_component(&AccountPanel.expectation/1, forecast: nil)
    refute html =~ "invitation-countdown"
    assert html =~ "Not earning" or html =~ "Complete an economic action"
  end

  test "operators see unlimited invitations without an earning or refund countdown" do
    forecast = %{
      "status" => "operator",
      "unlimited" => true,
      "remaining_ms" => nil,
      "refund_ms" => nil
    }

    html = render_component(&AccountPanel.expectation/1, forecast: forecast)
    assert html =~ "Unlimited invitations"
    refute html =~ "Available invitations: 0"
    refute html =~ "Next invitation"
    refute html =~ "invitation-countdown"
    refute html =~ "Complete an economic action"

    Localization.with_locale("ar", fn ->
      translated = render_component(&AccountPanel.expectation/1, forecast: forecast)
      refute translated =~ "Unlimited invitations"
      assert translated =~ ~r/\p{Arabic}/u
    end)
  end

  test "shows remaining earning time with active-world and continuing-operation conditions" do
    html = render_forecast("earning", 86_400_000)
    assert html =~ "Available invitations: 0"
    assert countdown(html) == "24:00:00"
    assert html =~ "Earning"
    assert html =~ "active-world time"
    assert html =~ "Counts down while your company stays active and solvent"
    assert html =~ "Pauses while the world is stopped"
    refute html =~ "An unused invitation returns"
  end

  test "blocked earning labels the full current requirement and gives the action required" do
    for {status, label, guidance} <- [
          {"inactive", "Not earning yet", "Complete an economic action worth at least $100"},
          {"no_company", "Not earning yet", "Form a company"},
          {"financial_trouble", "Paused", "Clear unpaid bills and loan arrears"},
          {"suspended", "Paused", "paused while your account is suspended"},
          {"capacity", "Paused", "resumes when an outstanding invitation is accepted"}
        ] do
      html = render_forecast(status)
      assert countdown(html) == "48:00:00"
      assert html =~ label
      assert html =~ guidance
    end
  end

  test "population-scaled periods render before earning and localize in Arabic" do
    for {period, days, countdown} <- [
          {0, "0", "00:00:00"},
          {86_400_000, "1", "24:00:00"},
          {259_200_000, "3", "72:00:00"}
        ] do
      html = render_forecast("inactive", period, nil, period)
      assert html =~ "Current earning period in active-world days: #{days}"
      assert html =~ "number of operating companies"
      assert countdown(html) == countdown
      refute html =~ "two days"
    end

    Localization.with_locale("ar", fn ->
      html = render_forecast("financial_trouble", 259_200_000, nil, 259_200_000)
      assert countdown(html) == "٧٢:٠٠:٠٠"
      assert html =~ "٣"
      refute html =~ "Current earning period"
      refute html =~ "Progress restarts"
    end)
  end

  test "unused expiry has its own conditional countdown, including when earning is blocked" do
    html = render_forecast("capacity", 172_800_000, 3_600_000)
    assert html =~ "An unused invitation returns in 01:00:00"
    assert html =~ "unless accepted first"
    assert countdown(render_forecast("earning", 1)) == "00:00:01"
    assert countdown(render_forecast("earning", 0)) == "00:00:00"
  end

  test "Arabic renders earning, expiry and blocked states with localized time" do
    Localization.with_locale("ar", fn ->
      html = render_forecast("earning", 86_400_000, 3_600_000)
      assert html =~ "الدعوة التالية"
      assert countdown(html) == "٢٤:٠٠:٠٠"
      assert html =~ ~s(dir="ltr")
      assert html =~ "٠١:٠٠:٠٠"
      refute html =~ "Next invitation"

      for status <- ~w(inactive no_company financial_trouble suspended capacity) do
        html = render_forecast(status)
        assert countdown(html) == "٤٨:٠٠:٠٠"
        text = html |> LazyHTML.from_fragment() |> LazyHTML.text()
        refute text =~ "invitation"
      end
    end)
  end
end
