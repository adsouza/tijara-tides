defmodule TijaraTides.Domain.ShipClass do
  @moduledoc "Immutable hull specifications shared by planning and ship operations."
  def all do
    %{
      "freighter" => %{
        "name" => "Balanced freighter",
        "price" => 4_000_000,
        "weight" => 500_000,
        "volume" => 900_000,
        "hold" => "dry",
        "speed" => 22,
        "crew" => 30
      },
      "small_freighter" => %{
        "name" => "Small freighter",
        "price" => 3_000_000,
        "weight" => 200_000,
        "volume" => 400_000,
        "hold" => "dry",
        "speed" => 24,
        "crew" => 20
      },
      "bulk" => %{
        "name" => "Bulk carrier",
        "price" => 5_000_000,
        "weight" => 1_000_000,
        "volume" => 1_200_000,
        "hold" => "dry",
        "speed" => 18,
        "crew" => 40
      },
      "reefer" => %{
        "name" => "Small refrigerated ship",
        "price" => 5_000_000,
        "weight" => 200_000,
        "volume" => 400_000,
        "hold" => "reefer",
        "speed" => 24,
        "crew" => 35
      },
      "tanker" => %{
        "name" => "Small tanker",
        "price" => 5_000_000,
        "weight" => 500_000,
        "volume" => 650_000,
        "hold" => "liquid",
        "speed" => 20,
        "crew" => 35
      }
    }
  end
end
