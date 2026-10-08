defmodule TijaraTides.UseCases.PiracyZonesQueryTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.Piracy
  alias TijaraTides.Infrastructure.GameCatalogue
  alias TijaraTides.UseCases.GameQueries

  test "levels follow announcement and start, chance follows the domain" do
    catalogue = GameCatalogue.all()
    model = Piracy.model(catalogue)

    c =
      Enum.find_value(1..1_000, fn slot ->
        Enum.find_value(Map.keys(model["zones"]), &Piracy.campaign(&1, slot, model))
      end)

    view = fn clock ->
      public = %{"clock_ms" => clock, "piracy" => Piracy.campaigns(clock, model)}
      Map.new(GameQueries.piracy_zones(public, catalogue), &{&1.id, &1})
    end

    assert view.(c["announced_ms"])[c["id"]].level == "elevated"
    assert view.(c["starts_ms"])[c["id"]].level == "campaign"

    assert view.(c["starts_ms"])[c["id"]].chance_bps ==
             Piracy.chance_bps(c["id"], c["starts_ms"], model)

    assert view.(c["until_ms"])[c["id"]].level == "normal"
    assert view.(c["until_ms"])[c["id"]].campaign == nil
    assert length(GameQueries.piracy_zones(%{"clock_ms" => 0}, catalogue)) == 5
    assert GameQueries.piracy_zones(%{"clock_ms" => 0}, %{}) == []
  end
end
