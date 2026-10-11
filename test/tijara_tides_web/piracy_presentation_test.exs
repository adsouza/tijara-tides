defmodule TijaraTidesWeb.PiracyPresentationTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias TijaraTidesWeb.GameUI.Presentation

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
end
