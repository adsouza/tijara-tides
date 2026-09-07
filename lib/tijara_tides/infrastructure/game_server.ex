defmodule TijaraTides.Infrastructure.GameServer do
  @moduledoc "Durable first-playtest owner; persistence precedes acknowledgement and publication."
  use GenServer
  require Logger
  alias TijaraTides.Domain.Game
  alias TijaraTides.Infrastructure.GameCatalogue
  alias TijaraTides.Infrastructure.Persistence.{GameStore, Repo}
  @topic "game:ocean"

  defp default_server, do: Application.get_env(:tijara_tides, :game_server, __MODULE__)

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def snapshot(token \\ nil, server \\ default_server()),
    do: GenServer.call(server, {:snapshot, token})

  def command(token, request, command, server \\ default_server()),
    do: GenServer.call(server, {:command, token, request, command}, 30_000)

  def preview(token, ship, destination, server \\ default_server()),
    do: GenServer.call(server, {:preview, token, ship, destination})

  def redeem(code, server \\ default_server()),
    do: GenServer.call(server, {:redeem, code}, 30_000)

  def seed(server \\ default_server()), do: GenServer.call(server, :seed, 30_000)
  def sign_out(token, server \\ default_server()), do: GenServer.call(server, {:sign_out, token})
  def connect(token, server \\ default_server()), do: GenServer.call(server, {:connect, token})
  def readiness(server \\ default_server()), do: GenServer.call(server, :readiness)
  def subscribe, do: Phoenix.PubSub.subscribe(TijaraTides.PubSub, @topic)

  def definitions,
    do: %{
      catalogue: GameCatalogue.all(),
      land: GameCatalogue.land(),
      regional_land: GameCatalogue.regional_land(),
      classes: Game.classes(),
      packages: Game.packages(),
      package_cash: Map.new(Game.packages(), fn {id, _} -> {id, Game.package_cash(id)} end)
    }

  def purchase_total(quote, ship, item, quantity),
    do: Game.purchase_total(quote, ship, item, quantity)

  def trade_freshness(quote, ship, side, good, quantity, clock) do
    batches =
      if side == "buy",
        do: quote["freshness_batches"],
        else: Enum.filter(ship["cargo"], &(&1["good"] == good))

    Game.freshness(batches, quantity, clock, Game.handling_ms(quantity))
  end

  def hash(token) when is_binary(token),
    do: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

  def hash(_), do: "invalid"
  def token, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  def request_id, do: Ecto.UUID.generate()

  @impl true
  def init(opts) do
    repo = Keyword.get(opts, :repo, Repo)
    enabled = Keyword.get(opts, :enabled, Application.get_env(:tijara_tides, :start_repo, false))

    state = %{
      repo: repo,
      world_id: Keyword.get(opts, :world_id, "ocean"),
      status: :not_configured,
      game: nil,
      catalogue: GameCatalogue.all(),
      active: false,
      last_mono: System.monotonic_time(:millisecond),
      tick_ms: Keyword.get(opts, :tick_ms, 5000),
      timer: nil
    }

    if enabled do
      try do
        {:ok, game} = GameStore.claim(repo, state.world_id)
        initialized = Game.initialize(game, state.catalogue)

        case GameStore.commit(repo, state.world_id, game.epoch, game, initialized) do
          {:ok, :ok} ->
            {:ok, %{state | game: TijaraTides.Domain.Journal.clear(initialized), status: :ready}}

          _ ->
            {:ok, %{state | status: :unavailable}}
        end
      rescue
        _ ->
          Logger.error("Game storage unavailable; apply game migrations before starting gameplay")
          {:ok, %{state | status: :unavailable}}
      end
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_call(:readiness, _from, state), do: {:reply, state.status, state}

  def handle_call({:snapshot, token}, _from, state) do
    view =
      if state.status == :ready do
        private =
          case account(state, token) do
            {:ok, a} ->
              private = Game.private(state.game, a)

              compatible =
                Map.new(private["ships"], fn {id, ship} ->
                  goods =
                    for {good, item} <- state.catalogue["goods"],
                        Game.compatible_cargo?(ship, item),
                        do: good

                  {id, goods}
                end)

              underway =
                Map.new(private["ships"], fn {id, ship} ->
                  estimates =
                    if ship["status"] == "sailing",
                      do:
                        Game.voyage_freshness(
                          ship,
                          state.game.clock_ms,
                          max(0, ship["arrive_ms"] - state.game.clock_ms)
                        ),
                      else: []

                  {id, estimates}
                end)

              private
              |> Map.put("compatible_cargo", compatible)
              |> Map.put("voyage_freshness", underway)

            _ ->
              nil
          end

        %{
          status: :ready,
          public: Game.public(state.game, state.catalogue),
          private: private,
          markets:
            Map.new(Game.entities(state.game, "markets"), fn {id, m} ->
              {id, Game.quote(state.game, state.catalogue, m["port"], m["good"])}
            end)
        }
      else
        %{status: state.status, public: nil, private: nil, markets: %{}}
      end

    {:reply, view, state}
  end

  def handle_call({:preview, token, id, destination}, _from, %{status: :ready} = state) do
    result =
      with {:ok, account} <- account(state, token),
           %{"company_id" => owner, "status" => "docked"} = ship <-
             Game.get(state.game, "ships", id),
           true <- owner == account["company_id"] do
        case Game.voyage_quote(ship, destination, state.catalogue) do
          nil ->
            nil

          quote ->
            Map.put(
              quote,
              "freshness",
              Game.voyage_freshness(ship, state.game.clock_ms, quote["duration_ms"])
            )
        end
      else
        _ -> nil
      end

    {:reply, result, state}
  end

  def handle_call({:connect, token}, _from, %{status: :ready} = state) do
    case account(state, token) do
      {:ok, _} ->
        if state.active && state.timer && Process.read_timer(state.timer) != false,
          do: {:reply, :ok, state},
          else:
            {:reply, :ok,
             %{
               state
               | active: true,
                 last_mono: System.monotonic_time(:millisecond),
                 timer: :erlang.start_timer(state.tick_ms, self(), :tick)
             }}

      _ ->
        {:reply, {:error, :invalid_session}, state}
    end
  end

  def handle_call(:seed, _from, %{status: :ready} = state) do
    code = token()

    case Game.seed_invite(state.game, hash(code)) do
      {:ok, game, result} -> finish(state, game, result, nil, fn _ -> {:ok, code} end)
      error -> {:reply, error, state}
    end
  end

  def handle_call({:redeem, code}, _from, %{status: :ready} = state)
      when is_binary(code) and byte_size(code) <= 100 do
    session = token()
    ctx = context(state)

    case Game.redeem(state.game, hash(String.trim(code)), hash(session), ctx) do
      {:ok, game, result} ->
        finish(state, game, result, nil, fn result ->
          {:ok, Map.put(result, "session", session)}
        end)

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:sign_out, token}, _from, %{status: :ready} = state) do
    game = Game.delete(state.game, "sessions", hash(token))
    finish(state, game, %{}, nil, fn _ -> :ok end)
  end

  def handle_call({:command, token, request, command}, _from, %{status: :ready} = state)
      when is_binary(request) and byte_size(request) in 1..128 and is_map(command) do
    with {:ok, a} <- account(state, token),
         true <- map_size(command) <= 12,
         true <- byte_size(:erlang.term_to_binary(command)) <= 4096 do
      fingerprint = hash(:erlang.term_to_binary(command))

      invite =
        :crypto.mac(
          :hmac,
          :sha256,
          Application.fetch_env!(:tijara_tides, :game_secret),
          "invite:" <> a["id"] <> ":" <> request
        )
        |> Base.url_encode64(padding: false)

      decorate = fn result ->
        if command["action"] == "invite", do: Map.put(result, "code", invite), else: result
      end

      # Receipts contain public results only, never plaintext credentials.
      try do
        case GameStore.receipt(state.repo, state.world_id, a["id"], request, fingerprint) do
          {:replay, result} ->
            {:reply, {:ok, decorate.(result)}, state}

          {:error, error} ->
            {:reply, {:error, error}, state}

          :new ->
            ctx = Map.put(context(state), :invite_hash, hash(invite))

            case TijaraTides.UseCases.GameCommands.execute(
                   state.game,
                   a,
                   command,
                   ctx,
                   state.catalogue
                 ) do
              {:ok, game, result} ->
                receipt = {a["id"], request, fingerprint, result}

                finish(state, game, result, receipt, fn result ->
                  {:ok,
                   if(command["action"] == "invite",
                     do: Map.put(result, "code", invite),
                     else: result
                   )}
                end)

              error ->
                {:reply, error, state}
            end
        end
      rescue
        _ ->
          {:reply, {:error, :storage_unavailable}, %{state | status: :unavailable, active: false}}
      end
    else
      _ -> {:reply, {:error, :invalid_session}, state}
    end
  end

  def handle_call(_request, _from, state), do: {:reply, {:error, state.status}, state}

  @impl true
  def handle_info({:timeout, timer, :tick}, %{timer: timer} = state),
    do: handle_info(:tick, state)

  def handle_info(:tick, %{status: :ready, active: true} = state) do
    now = System.monotonic_time(:millisecond)
    elapsed = max(0, now - state.last_mono)
    game = Game.advance(state.game, elapsed, state.catalogue)

    case persist(state, game, nil) do
      {:ok, next} ->
        if state.timer, do: Process.cancel_timer(state.timer)

        {:noreply,
         %{next | last_mono: now, timer: :erlang.start_timer(state.tick_ms, self(), :tick)}}

      {:error, reason} ->
        Logger.error("World progression paused: #{reason}")
        {:noreply, %{state | active: false, status: :unavailable}}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp context(state),
    do: %{id: request_id(), wall_ms: System.system_time(:millisecond), catalogue: state.catalogue}

  defp account(state, token),
    do: Game.authenticate(state.game, hash(token), System.system_time(:millisecond))

  defp finish(state, game, result, receipt, reply) do
    case persist(state, game, receipt) do
      {:ok, next} -> {:reply, reply.(result), next}
      {:error, {:replay, result}} -> {:reply, reply.(result), state}
      {:error, error} -> {:reply, {:error, error}, %{state | status: :unavailable, active: false}}
    end
  end

  defp persist(state, game, receipt) do
    game = %{game | revision: state.game.revision + 1}

    case GameStore.commit(state.repo, state.world_id, game.epoch, state.game, game, receipt) do
      {:ok, :ok} ->
        Phoenix.PubSub.broadcast(TijaraTides.PubSub, @topic, {:game_changed, game.revision})
        {:ok, %{state | game: TijaraTides.Domain.Journal.clear(game)}}

      error ->
        error
    end
  rescue
    _ -> {:error, :storage_unavailable}
  end
end
