defmodule TijaraTidesWeb.AccountPanelTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias TijaraTides.Localization
  alias TijaraTidesWeb.GameUI.AccountPanel

  defp render_forecast(status, remaining \\ 86_400_000, refund \\ nil) do
    render_component(&AccountPanel.expectation/1,
      forecast: %{"status" => status, "remaining_ms" => remaining, "refund_ms" => refund}
    )
  end

  test "shows remaining earning time with active-world and continuing-operation conditions" do
    html = render_forecast("earning")
    assert html =~ "Available invitations: 0"
    assert html =~ "Next invitation in 24:00:00"
    assert html =~ "active-world time"
    assert html =~ "if your company stays active and solvent"
    refute html =~ "An unused invitation returns"
  end

  test "blocked earning gives the action required instead of a misleading countdown" do
    for {status, guidance} <- [
          {"inactive", "Complete an economic action worth at least $100"},
          {"no_company", "Form a company"},
          {"financial_trouble", "Clear unpaid bills and loan arrears"},
          {"suspended", "paused while your account is suspended"},
          {"capacity", "resumes when an outstanding invitation is accepted"}
        ] do
      html = render_forecast(status)
      assert html =~ guidance
      refute html =~ "Next invitation in"
    end
  end

  test "unused expiry has its own conditional countdown, including when earning is blocked" do
    html = render_forecast("capacity", 172_800_000, 3_600_000)
    assert html =~ "An unused invitation returns in 01:00:00"
    assert html =~ "unless accepted first"
    assert render_forecast("earning", 1) =~ "Next invitation in 00:00:01"
  end

  test "Arabic renders earning, expiry and blocked states with localized time" do
    Localization.with_locale("ar", fn ->
      html = render_forecast("earning", 86_400_000, 3_600_000)
      assert html =~ "دعوتك التالية"
      assert html =~ "٢٤:٠٠:٠٠"
      assert html =~ "٠١:٠٠:٠٠"
      refute html =~ "Next invitation"

      for status <- ~w(inactive no_company financial_trouble suspended capacity) do
        text = render_forecast(status) |> LazyHTML.from_fragment() |> LazyHTML.text()
        refute text =~ "invitation"
      end
    end)
  end
end
