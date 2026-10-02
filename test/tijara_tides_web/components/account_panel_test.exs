defmodule TijaraTidesWeb.AccountPanelTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias TijaraTides.Localization
  alias TijaraTidesWeb.GameUI.AccountPanel

  defp render_forecast(status, remaining \\ 172_800_000, refund \\ nil) do
    render_component(&AccountPanel.expectation/1,
      forecast: %{"status" => status, "remaining_ms" => remaining, "refund_ms" => refund}
    )
  end

  defp countdown(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#invitation-countdown")
    |> LazyHTML.text()
    |> String.trim()
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

  test "blocked earning labels the full two-day requirement and gives the action required" do
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
