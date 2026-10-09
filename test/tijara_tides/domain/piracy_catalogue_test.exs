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

  test "every zone and campaign name is translatable" do
    model = Piracy.model(GameCatalogue.all())

    for {_, zone} <- model["zones"], name <- [zone["name"] | zone["campaign_names"]] do
      assert TijaraTides.Localization.with_locale("ar", fn ->
               TijaraTides.Localization.l10n(name)
             end) != name
    end
  end
end
