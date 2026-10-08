defmodule TijaraTides.UseCases.FleetQueries do
  @moduledoc "Grouping of the public fleet for visitors without a company."

  @doc """
  Groups every public ship by `"location"`, `"company"` or `"class"`.

  Location uses the map's regions: a port outside every cluster is its own
  region. Ships in port group by their port's region; ships at sea by the two
  regions at either end in either direction, or `:within` one region. In-port
  groups precede sea routes; a region's own voyages precede routes leaving it.
  """
  def public_fleet_groups(definitions, public, grouping) do
    region = port_regions(definitions.catalogue)

    public["ships"]
    |> Map.values()
    |> Enum.group_by(&group_key(&1, grouping, region))
    |> Enum.map(fn {key, ships} ->
      %{key: key, ships: Enum.sort_by(ships, &{&1["name"], &1["id"]})}
    end)
    |> Enum.sort_by(&order(&1.key, definitions, public))
  end

  defp group_key(ship, "company", _region), do: {:company, ship["company_id"]}
  defp group_key(ship, "class", _region), do: {:class, ship["class"]}

  defp group_key(%{"status" => "sailing"} = ship, _location, region) do
    case Enum.sort([region.(ship["port"]), region.(ship["destination"])]) do
      [same, same] -> {:within, same}
      [first, second] -> {:route, first, second}
    end
  end

  defp group_key(ship, _location, region), do: {:port, region.(ship["port"])}

  defp port_regions(catalogue) do
    regions =
      for {name, ports} <- catalogue["clusters"] || %{},
          port <- ports,
          into: %{},
          do: {port, name}

    &Map.get(regions, &1, &1)
  end

  defp order({:port, region}, _definitions, _public), do: {0, region, ""}
  defp order({:route, first, second}, _definitions, _public), do: {1, first, second}
  defp order({:within, region}, _definitions, _public), do: {1, region, region}

  defp order({:company, id}, _definitions, public),
    do: {0, get_in(public, ["companies", id, "name"]) || id || "", id || ""}

  defp order({:class, id}, definitions, _public),
    do: {0, get_in(definitions.classes, [id, "name"]) || id || "", id || ""}
end
