defmodule TijaraTidesWeb.WorldMapTest do
  use ExUnit.Case, async: true
  alias TijaraTidesWeb.WorldMap

  test "an underway ship remains renderable after its route is removed" do
    catalogue = TijaraTides.Infrastructure.GameCatalogue.all()
    catalogue = Map.put(catalogue, "routes", %{})

    ship = %{
      "status" => "sailing",
      "port" => "Hamburg",
      "destination" => "Rotterdam",
      "depart_ms" => 0,
      "arrive_ms" => 1000
    }

    assert TijaraTidesWeb.GameLive.ship_coordinates(ship, 500, catalogue) ==
             catalogue["ports"]["Hamburg"]["coordinates"]
  end

  test "route arrows follow travel direction, including short routes and seam crossings" do
    [east] = WorldMap.route_arrows([[0, 0], [0.1, 0]], 1)
    [west] = WorldMap.route_arrows([[0.1, 0], [0, 0]], 1)
    assert east.angle == 0
    assert abs(west.angle) == 180
    assert WorldMap.route_arrows([[0, 0], [0, 0]], 1) == []
    arrows = WorldMap.route_arrows([[179, 0], [-179, 0]], 0.04)
    assert arrows != []
    assert Enum.all?(arrows, &(&1.angle == 0))
  end

  test "Equal Earth bends meridians inward and preserves equatorial symmetry" do
    assert [500.0, 250.0] == WorldMap.project([0, 0])
    [equator, _] = WorldMap.project([180, 0])
    [polar, _] = WorldMap.project([180, 90])
    assert equator > polar and polar > 500
    [west, _] = WorldMap.project([-180, 0])
    assert_in_delta equator + west, 1000, 0.000001
  end

  test "regions cover the roster once and zoom bounds include every member harbor" do
    catalogue = TijaraTides.Infrastructure.GameCatalogue.all()
    regions = WorldMap.regions(catalogue)
    assert length(regions) == 20

    assert Enum.sort(Enum.flat_map(regions, & &1.ports)) ==
             Enum.sort(Map.keys(catalogue["ports"]))

    pearl = Enum.find(regions, &(&1.name == "Pearl River Delta"))
    assert pearl.ports == ["Guangzhou", "Hong Kong", "Shenzhen"]

    assert Enum.find(regions, &(&1.name == "Northern Frangistan")).ports ==
             ["Antwerp", "Hamburg", "Rotterdam"]

    for {region, ports} <- catalogue["clusters"] do
      viewport = WorldMap.viewport(catalogue, region)

      [x, y, width, height] =
        viewport.box
        |> String.split()
        |> Enum.map(fn s ->
          {number, ""} = Float.parse(s)
          number
        end)

      assert viewport.scale < 1

      for port <- ports do
        [px, py] = WorldMap.project(catalogue["ports"][port]["coordinates"])
        assert px > x and px < x + width and py > y and py < y + height
      end

      assert Enum.map(WorldMap.markers(catalogue, region), & &1.name) == Enum.sort(ports)
    end
  end

  test "crossing legs reach both seam edges without false cross-world lines" do
    assert [[[170, 10], [180, 15.0]], [[-180, 15.0], [-170, 20]]] ==
             WorldMap.segments([[170, 10], [-170, 20]])

    assert [[[-170, 20], [-180, 15.0]], [[180, 15.0], [170, 10]]] ==
             WorldMap.segments([[-170, 20], [170, 10]])

    segments = WorldMap.segments([[164.183239, 44.859607], [180, 50]])
    assert hd(segments) == [[164.183239, 44.859607], [180, 50.0]]
    for [[a, _], [b, _]] <- segments, do: assert(abs(b - a) <= 180)
  end
end
