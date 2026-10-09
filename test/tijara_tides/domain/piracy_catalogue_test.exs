defmodule TijaraTides.Domain.PiracyCatalogueTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.Piracy
  alias TijaraTides.Domain.VoyageNavigation
  alias TijaraTides.Infrastructure.GameCatalogue

  # Campaign windows captured from the phase 1 catalogue before phase 1b changed
  # any zone. They pin the seed, zone ids, period and start-offset hashing; the
  # campaign chance only decides whether a slot rolls at all.
  @phase_1_windows [
    {"caribbean", 21, 937_720_920},
    {"caribbean", 28, 1_240_262_164},
    {"caribbean", 29, 1_266_596_302},
    {"gulf_of_aden", 2, 114_240_685},
    {"gulf_of_aden", 5, 233_395_610},
    {"gulf_of_aden", 9, 395_937_102},
    {"malacca", 1, 58_345_387},
    {"malacca", 11, 496_437_364},
    {"malacca", 16, 707_454_840},
    {"red_sea", 11, 485_618_209},
    {"red_sea", 14, 606_990_024},
    {"red_sea", 17, 752_006_093},
    {"south_china_sea", 5, 232_632_582},
    {"south_china_sea", 7, 313_145_545},
    {"south_china_sea", 9, 412_836_616}
  ]

  # Sample each leg the way voyages interpolate, across the antimeridian too.
  defp crosses?(coordinates, ring) do
    coordinates
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(fn [[x, y], [u, v]] ->
      [dx, _] = VoyageNavigation.normalize([u - x, 0])
      Enum.any?(0..40, &Piracy.inside?([x + dx * &1 / 40, y + (v - y) * &1 / 40], ring))
    end)
  end

  defp zones_on(coordinates, zones),
    do: for({id, zone} <- Enum.sort(zones), crosses?(coordinates, zone["polygon"]), do: id)

  test "the generated catalogue carries eight valid zones on real routes" do
    catalogue = GameCatalogue.all()
    model = Piracy.validate!(Piracy.model(catalogue))

    assert Enum.sort(Map.keys(model["zones"])) ==
             ~w(barbary_coast caribbean english_channel gulf_of_aden malacca red_sea singapore_strait south_china_sea)

    assert model["zones"]["red_sea"]["kind"] == "militia"
    assert model["kinds"]["militia"]["mark"] == "💥"
    assert model["kinds"]["piracy"]["mark"] == "🏴‍☠️"
    refute Map.has_key?(model, "salt")

    for {id, zone} <- model["zones"] do
      for {port, %{"coordinates" => point}} <- catalogue["ports"],
          do: refute(Piracy.inside?(point, zone["polygon"]), "#{port} lies inside #{id}")

      assert Piracy.inside?(zone["label"], zone["polygon"])
    end

    # These are the counts docs/IMPLEMENTATION.md publishes.
    crossed =
      Map.new(model["zones"], fn {id, zone} ->
        {id,
         Enum.count(catalogue["routes"], &crosses?(elem(&1, 1)["coordinates"], zone["polygon"]))}
      end)

    assert crossed == %{
             "red_sea" => 202,
             "gulf_of_aden" => 206,
             "singapore_strait" => 194,
             "malacca" => 194,
             "south_china_sea" => 220,
             "caribbean" => 76,
             "english_channel" => 128,
             "barbary_coast" => 192
           }

    assert model["zones"]["malacca"]["chance_bps"] == 150
    assert model["zones"]["singapore_strait"]["chance_bps"] == 600
  end

  test "lanes, not just ports, fall where the zones intend" do
    catalogue = GameCatalogue.all()
    zones = Piracy.model(catalogue)["zones"]
    on = fn key -> zones_on(catalogue["routes"][key]["coordinates"], zones) end

    assert on.("Tangier|Valencia") == []
    assert on.("Hong Kong|Guangzhou") == []
    assert on.("Tangier|Athens") == ["barbary_coast"]
    assert "singapore_strait" in on.("Singapore|Busan")
    refute "malacca" in on.("Singapore|Busan")

    assert on.("Antwerp|Busan") ==
             ~w(barbary_coast english_channel gulf_of_aden malacca red_sea singapore_strait south_china_sea)
  end

  test "the original five zones keep their phase 1 campaign windows" do
    model = Piracy.model(GameCatalogue.all())

    for {id, slot, starts} <- @phase_1_windows,
        do: assert(Piracy.campaign(id, slot, model)["starts_ms"] == starts)
  end

  # Great-circle distance from a harbour to the nearest sampled edge point;
  # edges are sampled at most every 0.01 degrees, as the generator does.
  defp harbour_nm(point, ring) do
    ring
    |> Enum.zip(tl(ring) ++ [hd(ring)])
    |> Enum.flat_map(fn {[x1, y1], [x2, y2]} ->
      steps = max(1, ceil(max(abs(x2 - x1), abs(y2 - y1)) / 0.01))
      for k <- 0..steps, do: [x1 + (x2 - x1) * k / steps, y1 + (y2 - y1) * k / steps]
    end)
    |> Enum.map(&TijaraTides.Domain.VoyageNavigation.distance(point, &1))
    |> Enum.min()
  end

  test "the buffer measure separates 11.9 from 12.1 nautical miles" do
    square = fn d -> [[d, -1.0], [d + 1, -1.0], [d + 1, 1.0], [d, 1.0]] end
    assert_in_delta harbour_nm([0.0, 0.0], square.(11.9 / 60.04)), 11.9, 0.05
    assert_in_delta harbour_nm([0.0, 0.0], square.(12.1 / 60.04)), 12.1, 0.05
  end

  test "every zone keeps 12 nautical miles clear of every harbour" do
    catalogue = GameCatalogue.all()

    for {id, zone} <- Piracy.model(catalogue)["zones"],
        {port, %{"coordinates" => point}} <- catalogue["ports"] do
      assert harbour_nm(point, zone["polygon"]) >= 12.0, "#{port} is within 12 nm of #{id}"
    end
  end

  test "Algiers corsairs read as the Regency's captains, not as Algeria's pirates" do
    # قراصنة means pirates, and الجزائر names both Algiers and Algeria.
    assert TijaraTides.Localization.with_locale("ar", fn ->
             TijaraTides.Localization.l10n("Algiers corsairs")
           end) == "رياس الجزائر"
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
