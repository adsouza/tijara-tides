defmodule TijaraTides.Domain.PortBerths do
  @moduledoc "Pure berth allocation policy. Queue tickets live with ships and commit with handling."
  alias TijaraTides.Domain.State

  def capacity(catalogue, port) do
    spec = catalogue["ports"][port] || %{}

    spec["berth_count"] ||
      %{"low" => 2, "med" => 4, "high" => 6}[get_in(spec, ["tiers", "berths"])] || 4
  end

  def ships(state, port),
    do:
      State.entities(state, "ships")
      |> Map.values()
      |> Enum.filter(&(&1["port"] == port and &1["status"] != "sailing"))

  def occupied?(ship),
    do: ship["status"] in ["loading", "unloading"] or not is_nil(ship["berth_granted_ms"])

  def queue(state, port),
    do:
      ships(state, port)
      |> Enum.filter(&(not is_nil(&1["berth_queued_ms"])))
      |> Enum.sort_by(&{&1["berth_queued_ms"], &1["id"]})

  def available?(state, ship, catalogue) do
    occupied?(ship) or
      ((ship["berth_retry_ms"] || 0) <= state.clock_ms and is_nil(ship["berth_queued_ms"]) and
         queue(state, ship["port"]) == [] and
         Enum.count(ships(state, ship["port"]), &occupied?/1) < capacity(catalogue, ship["port"]))
  end

  def position(state, ship),
    do:
      Enum.find_index(queue(state, ship["port"]), &(&1["id"] == ship["id"]))
      |> then(&if(is_nil(&1), do: nil, else: &1 + 1))
end
