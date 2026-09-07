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
  def all, do: @catalogue
end
