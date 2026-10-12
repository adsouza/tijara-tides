defmodule TijaraTides.Domain.VoyagePathBoundsTest do
  # A departing ship stores its catalogue route in game_ship_voyage_points, whose
  # checks run inside the commit. A route outside them would pause the world on
  # the first departure, so the catalogue must stay within the stored bounds:
  # longitude -540..540 (continuous across the antimeridian), latitude -90..90.
  use ExUnit.Case, async: true
  alias TijaraTides.Infrastructure.GameCatalogue

  test "every catalogue route fits the stored voyage path bounds" do
    routes = GameCatalogue.all()["routes"]
    points = for {_, route} <- routes, point <- route["coordinates"], do: point

    assert Enum.any?(points, fn [x, _] -> x > 180 end), "routes cross the antimeridian"

    outside =
      Enum.reject(points, fn [x, y] -> x >= -540 and x <= 540 and y >= -90 and y <= 90 end)

    assert outside == []
  end
end
