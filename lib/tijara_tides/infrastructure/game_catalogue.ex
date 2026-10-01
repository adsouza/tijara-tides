defmodule TijaraTides.Infrastructure.GameCatalogue do
  @moduledoc "Versioned static definitions, loaded once and excluded from durable entity writes."
  @external_resource Path.expand("../../../priv/game/catalogue.json", __DIR__)
  @catalogue @external_resource |> File.read!() |> Jason.decode!()
  @land_path Path.expand("../../../priv/game/land.json", __DIR__)
  @external_resource @land_path
  @land @land_path |> File.read!() |> Jason.decode!()
  @regional_land_path Path.expand("../../../priv/game/regional-land.json", __DIR__)
  @external_resource @regional_land_path
  @regional_land @regional_land_path |> File.read!() |> Jason.decode!()
  def regional_land, do: @regional_land
  def land, do: @land

  def all do
    @catalogue
    |> Map.update!("weather", &Map.merge(&1, Application.get_env(:tijara_tides, :weather, %{})))
    |> Map.put(
      "departure_funding",
      TijaraTides.Domain.Automation.settings(%{
        "departure_funding" => Application.get_env(:tijara_tides, :departure_funding, %{})
      })
    )
    |> Map.put("auctions", Application.get_env(:tijara_tides, :auctions, %{}))
    |> Map.put(
      "dormancy",
      TijaraTides.Domain.Account.dormancy_settings(%{
        "dormancy" => Application.get_env(:tijara_tides, :dormancy, %{})
      })
    )
  end
end
