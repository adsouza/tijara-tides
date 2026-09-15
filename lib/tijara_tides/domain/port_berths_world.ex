defmodule TijaraTides.Domain.PortBerthsWorld do
  @moduledoc "Loads the current fleet for pure port capacity and admission decisions."
  alias TijaraTides.Domain.{PortBerths, ReadState}

  def load(state, port, catalogue), do: PortBerths.from_fleet(port, ships(state, port), catalogue)

  @doc "Every port's model from one pass over the fleet, for callers that need them all."
  def load_all(state, catalogue) do
    berthed =
      ReadState.entities(state, "ships")
      |> Map.values()
      |> Enum.reject(&(&1["status"] == "sailing"))
      |> Enum.group_by(& &1["port"])

    Map.new(catalogue["ports"], fn {port, _} ->
      {port, PortBerths.from_fleet(port, Map.get(berthed, port, []), catalogue)}
    end)
  end

  def ships(state, port),
    do:
      ReadState.entities(state, "ships")
      |> Map.values()
      |> Enum.filter(&(&1["port"] == port and &1["status"] != "sailing"))

  def available?(state, ship, catalogue),
    do:
      PortBerths.available?(
        ships(state, ship["port"]),
        ship,
        state.clock_ms,
        PortBerths.capacity(catalogue, ship["port"])
      )
end
