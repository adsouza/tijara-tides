defmodule TijaraTides.Domain.PortBerths do
  @moduledoc "Port-level capacity and FIFO admission model. Decisions commit with ship transitions in one world transaction."
  alias TijaraTides.Domain.State

  @enforce_keys [:port, :capacity, :held, :waiting]
  defstruct [:port, :capacity, :held, :waiting, positions: %{}]

  def load(state, port, catalogue), do: from_fleet(port, ships(state, port), catalogue)

  @doc "Every port's model from one pass over the fleet, for callers that need them all."
  def load_all(state, catalogue) do
    berthed =
      State.entities(state, "ships")
      |> Map.values()
      |> Enum.reject(&(&1["status"] == "sailing"))
      |> Enum.group_by(& &1["port"])

    Map.new(catalogue["ports"], fn {port, _} ->
      {port, from_fleet(port, Map.get(berthed, port, []), catalogue)}
    end)
  end

  defp from_fleet(port, fleet, catalogue) do
    waiting = fleet |> Enum.filter(&queued?/1) |> Enum.sort_by(&{&1["berth_queued_ms"], &1["id"]})

    %__MODULE__{
      port: port,
      capacity: capacity(catalogue, port),
      held: held(fleet),
      waiting: waiting,
      positions: index_positions(waiting)
    }
  end

  defp index_positions(waiting),
    do:
      waiting |> Enum.with_index(1) |> Map.new(fn {ship, position} -> {ship["id"], position} end)

  defp held(fleet), do: fleet |> Enum.filter(&occupied?/1) |> MapSet.new(& &1["id"])
  defp queued?(ship), do: not is_nil(ship["berth_queued_ms"])

  @doc "Where a ship sits in its port's queue, counting from 1, or nil when it holds no ticket."
  def position(%__MODULE__{} = port, id), do: Map.get(port.positions, id)

  @doc "Decide admission in ticket order; eligibility is supplied without changing the port."
  def allocate(%__MODULE__{} = port, eligibility) do
    {next, decisions} = allocate_queue(port.waiting, port, eligibility, [])
    {%{next | positions: index_positions(next.waiting)}, decisions}
  end

  defp allocate_queue([], port, _, decisions), do: {port, Enum.reverse(decisions)}

  defp allocate_queue([ship | rest] = waiting, port, eligibility, decisions) do
    if MapSet.size(port.held) >= port.capacity do
      {%{port | waiting: waiting}, Enum.reverse(decisions)}
    else
      decision = eligibility.(ship)

      unless decision in [:grant, :release, :retry],
        do: raise(ArgumentError, "Unknown berth eligibility decision")

      held = if decision == :grant, do: MapSet.put(port.held, ship["id"]), else: port.held

      allocate_queue(rest, %{port | held: held, waiting: rest}, eligibility, [
        {ship["id"], decision} | decisions
      ])
    end
  end

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

  # Admission only asks whether anyone is ahead and whether a berth is free, so it skips
  # the ticket ordering allocate/2 needs — this runs on every trade.
  def available?(state, ship, catalogue) do
    fleet = ships(state, ship["port"])
    held = held(fleet)

    MapSet.member?(held, ship["id"]) or
      ((ship["berth_retry_ms"] || 0) <= state.clock_ms and is_nil(ship["berth_queued_ms"]) and
         not Enum.any?(fleet, &queued?/1) and
         MapSet.size(held) < capacity(catalogue, ship["port"]))
  end
end
