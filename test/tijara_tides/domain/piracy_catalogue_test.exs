defmodule TijaraTides.Domain.PiracyCatalogueTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.Piracy
  alias TijaraTides.Infrastructure.GameCatalogue

  test "the generated catalogue carries five valid zones on real routes" do
    catalogue = GameCatalogue.all()
    model = Piracy.validate!(Piracy.model(catalogue))

    assert Enum.sort(Map.keys(model["zones"])) ==
             ~w(caribbean gulf_of_aden malacca red_sea south_china_sea)

    assert model["zones"]["red_sea"]["kind"] == "militia"
    assert model["kinds"]["militia"]["mark"] == "💥"
    assert model["kinds"]["piracy"]["mark"] == "🏴‍☠️"
    refute Map.has_key?(model, "salt")

    for {id, zone} <- model["zones"] do
      for {port, %{"coordinates" => point}} <- catalogue["ports"],
          do: refute(Piracy.inside?(point, zone["polygon"]), "#{port} lies inside #{id}")

      assert Piracy.inside?(zone["label"], zone["polygon"])

      crossed =
        Enum.count(catalogue["routes"], fn {_, r} ->
          Enum.any?(r["coordinates"], &Piracy.inside?(&1, zone["polygon"]))
        end)

      assert crossed > 0, "no route vertex lies in #{id}"
    end
  end

  test "every zone and campaign name is translatable" do
    model = Piracy.model(GameCatalogue.all())

    for {_, zone} <- model["zones"], name <- [zone["name"] | zone["campaign_names"]] do
      assert TijaraTides.Localization.with_locale("ar", fn ->
               TijaraTides.Localization.l10n(name)
             end) != name
    end
  end
end
