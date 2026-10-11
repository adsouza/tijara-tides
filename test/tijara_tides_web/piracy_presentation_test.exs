defmodule TijaraTidesWeb.PiracyPresentationTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias TijaraTidesWeb.GameUI.Presentation

  test "protection controls and retained cover render in English and Arabic" do
    {state, cat} = TijaraTides.CommandFuzzer.fixture()
    ship = state.entities["ships"]["company:1"] |> Map.put("port", "Tangier")
    quote = TijaraTides.Domain.Fleet.voyage_quote(ship, "Athens", cat, 0, nil, "both")

    for {locale, guards, insurance} <- [
          {"en", "Armed guards", "Voyage insurance"},
          {"ar", "حراس مسلحون", "تأمين الرحلة"}
        ] do
      html =
        TijaraTides.Localization.with_locale(locale, fn ->
          render_component(&Presentation.protection_quote/1, quote: quote)
        end)

      assert html =~ guards
      assert html =~ insurance
      assert html =~ ~s(aria-checked="true")
      assert html =~ "🏴‍☠️"

      sailing =
        TijaraTides.Localization.with_locale(locale, fn ->
          render_component(&Presentation.protection_quote/1, quote: quote, sailing: true)
        end)

      refute sailing =~ ~s(phx-click="voyage-protection")
      assert sailing =~ guards
    end
  end

  test "both marks accompany a readable localized held label, with no charge on the public status" do
    for {kind, mark, label, arabic} <- [
          {"piracy", "🏴‍☠️", "Held by pirates", "محتجز لدى القراصنة"},
          {"militia", "💥", "Repairing strike damage", "إصلاح أضرار الضربة"}
        ] do
      hold = %{
        "source" => "piracy",
        "kind" => kind,
        "mark" => mark,
        "label" => label,
        "zone_name" => "Barbary Coast",
        "starts_ms" => 1000,
        "until_ms" => 61_000
      }

      ship = %{"status" => "sailing", "weather" => %{"holds" => [hold], "delay_ms" => 60_000}}

      for {locale, text} <- [{"en", label}, {"ar", arabic}] do
        html =
          TijaraTides.Localization.with_locale(locale, fn ->
            render_component(&Presentation.weather_notice/1, ship: ship, clock: 1001)
          end)

        assert html =~ text
        assert html =~ mark
        refute html =~ "weather-delay"
        refute html =~ "Charge"
      end
    end
  end

  test "no-protection labels and changed diversion prices have specific localized messages" do
    {state, cat} = TijaraTides.CommandFuzzer.fixture()
    ship = state.entities["ships"]["company:1"] |> Map.put("port", "Tangier")
    quote = TijaraTides.Domain.Fleet.voyage_quote(ship, "Athens", cat, 0)

    for {locale, label, price} <- [
          {"en", "No protection", "Protection prices changed"},
          {"ar", "بدون حماية", "تغيرت أسعار الحماية"}
        ] do
      {html, message} =
        TijaraTides.Localization.with_locale(locale, fn ->
          {render_component(&Presentation.protection_quote/1, quote: quote, sailing: true),
           Presentation.error_message(:departure_protection_changed)}
        end)

      assert html =~ label
      assert message =~ price
    end
  end
end
