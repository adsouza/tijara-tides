defmodule TijaraTides.Domain.PortBerths do
  @moduledoc "Port-level capacity and FIFO admission model. Decisions commit with ship transitions in one world transaction."
  alias TijaraTides.Domain.State

  @enforce_keys [:port, :capacity, :held, :waiting]
  defstruct [:port, :capacity, :held, :waiting]

  def load(state, port, catalogue) do
    fleet = ships(state, port)

    %__MODULE__{
      port: port,
      capacity: capacity(catalogue, port),
      held: fleet |> Enum.filter(&occupied?/1) |> MapSet.new(& &1["id"]),
      waiting:
        fleet
        |> Enum.filter(&(not is_nil(&1["berth_queued_ms"])))
        |> Enum.sort_by(&{&1["berth_queued_ms"], &1["id"]})
    }
  end

  @doc "Decide admission in ticket order; eligibility is supplied without changing the port."
  def allocate(%__MODULE__{} = port, eligibility) do
    allocate_queue(port.waiting, port, eligibility, [])
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

  def queue(state, port),
    do:
      ships(state, port)
      |> Enum.filter(&(not is_nil(&1["berth_queued_ms"])))
      |> Enum.sort_by(&{&1["berth_queued_ms"], &1["id"]})

  def available?(state, ship, catalogue) do
    port = load(state, ship["port"], catalogue)

    MapSet.member?(port.held, ship["id"]) or
      ((ship["berth_retry_ms"] || 0) <= state.clock_ms and is_nil(ship["berth_queued_ms"]) and
         port.waiting == [] and MapSet.size(port.held) < port.capacity)
  end

  def position(state, ship),
    do:
      Enum.find_index(queue(state, ship["port"]), &(&1["id"] == ship["id"]))
      |> then(&if(is_nil(&1), do: nil, else: &1 + 1))
end
