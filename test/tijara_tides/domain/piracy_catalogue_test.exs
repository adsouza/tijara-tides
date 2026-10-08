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
    end

    # Sample each leg the way voyages interpolate, across the antimeridian too;
    # these are the counts docs/IMPLEMENTATION.md publishes.
    crossed =
      Map.new(model["zones"], fn {id, zone} ->
        {id,
         Enum.count(catalogue["routes"], fn {_, route} ->
           route["coordinates"]
           |> Enum.chunk_every(2, 1, :discard)
           |> Enum.any?(fn [[x, y], [u, v]] ->
             [dx, _] = TijaraTides.Domain.VoyageNavigation.normalize([u - x, 0])

             Enum.any?(0..40, fn k ->
               Piracy.inside?([x + dx * k / 40, y + (v - y) * k / 40], zone["polygon"])
             end)
           end)
         end)}
      end)

    assert crossed == %{
             "red_sea" => 202,
             "gulf_of_aden" => 206,
             "malacca" => 194,
             "south_china_sea" => 220,
             "caribbean" => 76
           }
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
