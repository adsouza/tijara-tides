defmodule TijaraTides.Domain.PiracyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias TijaraTides.Domain.Piracy

  defp model(overrides \\ %{}) do
    Map.merge(
      %{
        "seed" => 7,
        "first_slot" => 1,
        "campaign" => %{
          "period_ms" => 100_000,
          "duration_ms" => 20_000,
          "warning_ms" => 5_000,
          "multiplier" => 4
        },
        "kinds" => %{
          "piracy" => kind("🏴‍☠️"),
          "fleet_piracy" => kind("🏴‍☠️"),
          "boarding" => kind("🏴‍☠️"),
          "militia" => kind("💥")
        },
        "zones" => %{
          "gulf_of_aden" => %{
            "name" => "Gulf of Aden",
            "kind" => "piracy",
            "chance_bps" => 400,
            "campaign_bps" => 10_000,
            "guard_pct" => 90,
            "campaign_names" => ["Somali Basin raids", "Gulf of Aden hijackings"],
            "polygon" => [[43.5, 11.0], [60.0, 8.0], [60.0, 19.0], [43.5, 13.1]],
            "label" => [52.0, 11.0]
          }
        }
      },
      overrides
    )
  end

  defp kind(mark),
    do: %{"mark" => mark, "hold_ms" => 600_000, "charge_bps" => 400, "storm_suppressed" => true}

  test "inside? uses the lon/lat plane with an even-odd rule" do
    ring = [[0, 0], [10, 0], [10, 10], [0, 10]]
    assert Piracy.inside?([5, 5], ring)
    refute Piracy.inside?([15, 5], ring)
    refute Piracy.inside?([5, -1], ring)
  end

  test "validate! accepts the model and rejects malformed campaigns and zones" do
    assert Piracy.validate!(model()) == model()
    assert Piracy.validate!(nil) == nil

    bad = [
      put_in(model(), ["campaign", "duration_ms"], 0),
      put_in(model(), ["campaign", "warning_ms"], 90_000),
      put_in(model(), ["campaign", "multiplier"], 0),
      put_in(model(), ["zones", "gulf_of_aden", "polygon"], [[0, 0], [1, 1]]),
      put_in(model(), ["zones", "gulf_of_aden", "kind"], "kraken"),
      put_in(model(), ["zones", "gulf_of_aden", "chance_bps"], 10_001),
      put_in(model(), ["zones", "gulf_of_aden", "campaign_names"], []),
      put_in(model(), ["kinds", "militia", "hold_ms"], 0),
      Map.update!(model(), "kinds", &Map.delete(&1, "boarding")),
      # The seeded start offset hashes into span + 1, which phash2 caps at 2^32.
      put_in(model(), ["campaign", "period_ms"], 60 * 86_400_000)
    ]

    for m <- bad, do: assert_raise(ArgumentError, fn -> Piracy.validate!(m) end)
  end

  test "the longest accepted campaign period still rolls without raising" do
    # span + 1 == 2^32, the largest range phash2 accepts.
    m =
      model()
      |> put_in(["campaign", "period_ms"], 4_294_967_295 + 20_000 + 5_000)

    assert Piracy.validate!(m) == m
    c = Piracy.campaign("gulf_of_aden", 1, m)
    assert c["until_ms"] <= 2 * m["campaign"]["period_ms"]

    assert_raise ArgumentError, fn ->
      Piracy.validate!(update_in(m, ["campaign", "period_ms"], &(&1 + 1)))
    end
  end

  test "no campaign rolls before the first slot" do
    assert Piracy.campaign("gulf_of_aden", 0, model()) == nil
    assert Piracy.campaigns(50_000, model()) == %{}
  end

  property "a campaign and its warning lie inside their own slot" do
    check all(slot <- integer(1..500), seed <- integer(0..1000)) do
      m = model(%{"seed" => seed})
      c = Piracy.campaign("gulf_of_aden", slot, m)
      assert c["announced_ms"] >= slot * 100_000
      assert c["starts_ms"] - c["announced_ms"] == 5_000
      assert c["until_ms"] - c["starts_ms"] == 20_000
      assert c["until_ms"] <= (slot + 1) * 100_000
      assert c["name"] in ["Somali Basin raids", "Gulf of Aden hijackings"]
      assert c["window_id"] == "gulf_of_aden:#{slot}"
    end
  end

  test "campaigns lists announced and running windows only" do
    c = Piracy.campaign("gulf_of_aden", 3, model())
    assert Piracy.campaigns(c["announced_ms"] - 1, model()) == %{}
    assert Piracy.campaigns(c["announced_ms"], model()) == %{"gulf_of_aden" => c}
    assert Piracy.campaigns(c["until_ms"] - 1, model()) == %{"gulf_of_aden" => c}
    assert Piracy.campaigns(c["until_ms"], model()) == %{}
    assert Piracy.campaigns(c["starts_ms"], nil) == %{}
  end

  test "chance multiplies only while the campaign runs, not while announced" do
    c = Piracy.campaign("gulf_of_aden", 3, model())
    refute Piracy.campaign_active?("gulf_of_aden", c["announced_ms"], model())
    assert Piracy.chance_bps("gulf_of_aden", c["announced_ms"], model()) == 400
    assert Piracy.campaign_active?("gulf_of_aden", c["starts_ms"], model())
    assert Piracy.chance_bps("gulf_of_aden", c["starts_ms"], model()) == 1600
    assert Piracy.chance_bps("gulf_of_aden", c["until_ms"], model()) == 400
  end

  test "zero campaign chance never rolls a campaign" do
    m = put_in(model(), ["zones", "gulf_of_aden", "campaign_bps"], 0)
    assert Enum.all?(1..200, &(Piracy.campaign("gulf_of_aden", &1, m) == nil))
  end
end
