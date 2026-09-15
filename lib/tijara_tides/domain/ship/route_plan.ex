defmodule TijaraTides.Domain.Ship.RoutePlan do
  @moduledoc "Typed repeating route snapshot owned by a ship."
  defstruct [:header, stops: [], targets: []]
end
