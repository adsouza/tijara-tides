defmodule TijaraTides.UseCases.FleetQueriesTest do
  use ExUnit.Case, async: true
  alias TijaraTides.UseCases.{FleetQueries, Game}

  @definitions Game.definitions()

  defp ship(id, company, class, status, port, destination \\ nil) do
    %{
      "id" => id,
      "name" => "Ship " <> id,
      "company_id" => company,
      "class" => class,
      "status" => status,
      "port" => port,
      "destination" => destination
    }
  end

  defp public(ships) do
    %{
      "companies" => %{
        "c1" => %{"id" => "c1", "name" => "Zephyr Lines"},
        "c2" => %{"id" => "c2", "name" => "Amber Shipping"}
      },
      "ships" => Map.new(ships, &{&1["id"], &1})
    }
  end

  defp summary(groups),
    do: Enum.map(groups, fn group -> {group.key, Enum.map(group.ships, & &1["id"])} end)

  test "location groups ports by region, then sea routes by their unordered regions, a region's own voyages first" do
    ships = [
      ship("1", "c1", "tanker", "docked", "Hamburg"),
      ship("2", "c2", "bulk", "loading", "Rotterdam"),
      ship("3", "c1", "bulk", "unloading", "Singapore"),
      ship("4", "c2", "reefer", "sailing", "Singapore", "Hamburg"),
      ship("5", "c1", "reefer", "sailing", "Antwerp", "Singapore"),
      ship("6", "c2", "tanker", "sailing", "Rotterdam", "Antwerp"),
      ship("7", "c1", "freighter", "sailing", "Jakarta", "Singapore"),
      ship("8", "c2", "freighter", "sailing", "Singapore", "Jakarta"),
      ship("9", "c1", "freighter", "docked", "Jakarta")
    ]

    assert summary(FleetQueries.public_fleet_groups(@definitions, public(ships), "location")) ==
             [
               {{:port, "Jakarta"}, ["9"]},
               {{:port, "Northern Frangistan"}, ["1", "2"]},
               {{:port, "Singapore"}, ["3"]},
               {{:route, "Jakarta", "Singapore"}, ["7", "8"]},
               {{:within, "Northern Frangistan"}, ["6"]},
               {{:route, "Northern Frangistan", "Singapore"}, ["4", "5"]}
             ]
  end

  test "company and class groups follow their display names, ships their own names" do
    ships = [
      ship("b", "c1", "tanker", "docked", "Hamburg"),
      ship("a", "c1", "bulk", "sailing", "Singapore", "Jakarta"),
      ship("c", "c2", "tanker", "docked", "Dubai")
    ]

    assert summary(FleetQueries.public_fleet_groups(@definitions, public(ships), "company")) ==
             [{{:company, "c2"}, ["c"]}, {{:company, "c1"}, ["a", "b"]}]

    names = Enum.map(["bulk", "tanker"], &@definitions.classes[&1]["name"])
    assert names == Enum.sort(names)

    assert summary(FleetQueries.public_fleet_groups(@definitions, public(ships), "class")) ==
             [{{:class, "bulk"}, ["a"]}, {{:class, "tanker"}, ["b", "c"]}]
  end

  test "an empty world has no groups" do
    assert FleetQueries.public_fleet_groups(@definitions, public([]), "location") == []
  end
end
