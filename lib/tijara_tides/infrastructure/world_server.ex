defmodule TijaraTides.Infrastructure.WorldServer do
  @moduledoc """
  Ephemeral presence roster for one world; GameServer owns durable gameplay.

  The roster is connection metadata, not persisted player/game state. Only this
  process owns it. Each attached process is monitored; multiple play tabs share one
  browser identity. Public snapshots never include session credentials or PIDs.
  """
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  def snapshot(server \\ __MODULE__), do: GenServer.call(server, :snapshot)
  def attach(server \\ __MODULE__, player_id), do: GenServer.call(server, {:attach, player_id})
  def detach(server \\ __MODULE__), do: GenServer.call(server, :detach)
  def command(server \\ __MODULE__, command), do: GenServer.call(server, {:command, command})
  def subscribe(world_id), do: Phoenix.PubSub.subscribe(TijaraTides.PubSub, topic(world_id))
  defp topic(world_id), do: "world:" <> world_id

  @impl true
  def init(opts) do
    {:ok, %{world: %{id: Keyword.get(opts, :world_id, "ocean")}, revision: 0, clients: %{}}}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, public_snapshot(state), state}

  def handle_call(:detach, {pid, _}, state) do
    case Map.pop(state.clients, pid) do
      {nil, _} ->
        {:reply, :ok, state}

      {{ref, _}, clients} ->
        Process.demonitor(ref, [:flush])
        {:reply, :ok, publish(%{state | clients: clients})}
    end
  end

  def handle_call({:attach, player_id}, {pid, _}, state)
      when is_binary(player_id) and byte_size(player_id) in 1..128 do
    case Map.fetch(state.clients, pid) do
      {:ok, {_ref, ^player_id}} ->
        {:reply, public_snapshot(state), state}

      {:ok, _other} ->
        {:reply, {:error, :already_attached}, state}

      :error ->
        state = %{state | clients: Map.put(state.clients, pid, {Process.monitor(pid), player_id})}
        state = publish(state)
        {:reply, public_snapshot(state), state}
    end
  end

  def handle_call({:attach, _}, _from, state), do: {:reply, {:error, :invalid_identity}, state}

  def handle_call({:command, _command}, {pid, _}, state) do
    result =
      case Map.fetch(state.clients, pid) do
        {:ok, _} -> {:error, :unsupported_command}
        :error -> {:error, :not_attached}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    case Map.fetch(state.clients, pid) do
      {:ok, {^ref, _}} ->
        {:noreply, publish(%{state | clients: Map.delete(state.clients, pid)})}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp publish(state) do
    state = %{state | revision: state.revision + 1}

    Phoenix.PubSub.broadcast(
      TijaraTides.PubSub,
      topic(state.world.id),
      {:world_updated, public_snapshot(state)}
    )

    state
  end

  defp public_snapshot(state) do
    %{
      world_id: state.world.id,
      revision: state.revision,
      online_players:
        state.clients |> Map.values() |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length(),
      connections: map_size(state.clients)
    }
  end
end
