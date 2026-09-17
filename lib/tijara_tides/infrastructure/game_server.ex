defmodule TijaraTides.Infrastructure.GameServer do
  @moduledoc "Durable first-playtest owner; persistence precedes acknowledgement and publication."
  use GenServer
  require Logger
  alias TijaraTides.Domain.Game
  alias TijaraTides.Infrastructure.{GameCatalogue, OperationBoundary}
  alias TijaraTides.Infrastructure.Persistence.{GameStore, Repo, ReportStore}
  @topic "game:ocean"
  @call_timeout 30_000

  defp default_server, do: Application.get_env(:tijara_tides, :game_server, __MODULE__)

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def snapshot(token \\ nil, server \\ default_server()),
    do: GenServer.call(server, {:snapshot, token}, @call_timeout)

  # The owner process only plans the page; the SQL runs here, in the caller, so a slow
  # or contended report read never queues behind or ahead of commands and world ticks.
  def reports(token, selection, server \\ default_server()) do
    reports_with_retry(token, selection, server, 2)
  end

  defp reports_with_retry(token, selection, server, retries) do
    result =
      case GenServer.call(server, {:report_plan, token, selection}, @call_timeout) do
        {:ok, plan, store} -> read_reports(plan, store)
        {:error, error} -> {:error, error}
      end

    case result do
      {:error, :report_revision_changed} when retries > 0 ->
        reports_with_retry(token, selection, server, retries - 1)

      other ->
        other
    end
  end

  defp read_reports(plan, store) do
    OperationBoundary.run(
      :report_query,
      fn -> TijaraTides.UseCases.ReportQueries.fetch(plan, store) end,
      fn _ -> {:error, :report_unavailable} end
    )
  end

  def command(token, request, command, server \\ default_server()),
    do: GenServer.call(server, {:command, token, request, command}, @call_timeout)

  def email_request(token, purpose, email, request_id, requester, server \\ default_server()),
    do:
      GenServer.call(
        server,
        {:email_request, token, purpose, email, request_id, requester},
        @call_timeout
      )

  def email_redeem(code, device, signed_in, server \\ default_server()),
    do: GenServer.call(server, {:email_redeem, code, device, signed_in}, @call_timeout)

  def email_pending(server \\ default_server()),
    do: GenServer.call(server, :email_pending, @call_timeout)

  def email_failed(id, server \\ default_server()),
    do: GenServer.call(server, {:email_failed, id}, @call_timeout)

  def email_delivered(id, server \\ default_server()),
    do: GenServer.call(server, {:email_delivered, id}, @call_timeout)

  def email_token(id),
    do:
      :crypto.mac(:hmac, :sha256, invite_key(), "email:" <> id)
      |> Base.url_encode64(padding: false)

  def preview(token, ship, destination, server \\ default_server()),
    do: GenServer.call(server, {:preview, token, ship, destination}, @call_timeout)

  def redeem(code, server \\ default_server()),
    do: redeem_for_device(code, token(), server)

  def redeem_for_device(code, device_token, server \\ default_server()),
    do: GenServer.call(server, {:redeem, code, device_token}, @call_timeout)

  def seed(server \\ default_server()), do: GenServer.call(server, :seed, @call_timeout)

  def sign_out(token, server \\ default_server()),
    do: GenServer.call(server, {:sign_out, token}, @call_timeout)

  def connect(token, server \\ default_server()),
    do: GenServer.call(server, {:connect, token}, @call_timeout)

  def readiness(server \\ default_server()), do: GenServer.call(server, :readiness, @call_timeout)
  def subscribe, do: Phoenix.PubSub.subscribe(TijaraTides.PubSub, @topic)

  def definitions,
    do: %{
      catalogue: GameCatalogue.all(),
      land: GameCatalogue.land(),
      regional_land: GameCatalogue.regional_land(),
      classes: Game.classes()
    }

  def cargo_name(good), do: GameCatalogue.all()["goods"][good]["name"] || good

  defdelegate destination_options(definitions, view, ship, destination),
    to: TijaraTides.Infrastructure.GameQueries

  defdelegate purchase_total(quote, ship, item, quantity),
    to: TijaraTides.Infrastructure.GameQueries

  defdelegate trade_freshness(quote, ship, side, good, quantity, clock),
    to: TijaraTides.Infrastructure.GameQueries

  defdelegate trade_limits(view, ship, destination), to: TijaraTides.Infrastructure.GameQueries

  defdelegate purchase_voyage(ship, item, quantity, destination, fleet, clock),
    to: TijaraTides.Infrastructure.GameQueries

  def hash(token) when is_binary(token),
    do: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

  def hash(_), do: nil
  def token, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  def request_id, do: Ecto.UUID.generate()

  @impl true
  def init(opts) do
    repo = Keyword.get(opts, :repo, Repo)
    enabled = Keyword.get(opts, :enabled, Application.get_env(:tijara_tides, :start_repo, false))

    state = %{
      repo: repo,
      wall_clock: Keyword.get(opts, :wall_clock, fn -> System.system_time(:millisecond) end),
      world_id: Keyword.get(opts, :world_id, "ocean"),
      status: :not_configured,
      game: nil,
      projection: nil,
      catalogue: GameCatalogue.all(),
      active: false,
      last_mono: System.monotonic_time(:millisecond),
      tick_ms: Keyword.get(opts, :tick_ms, 3000),
      tick_schedule: TijaraTides.Infrastructure.TickSchedule.new(opts),
      timer: nil,
      tick_due_mono: nil
    }

    if enabled do
      OperationBoundary.run(
        :initialization,
        fn ->
          {:ok, game} =
            GameStore.claim(repo, state.world_id, wall_ms: state.wall_clock.())

          result =
            TijaraTides.UseCases.CommitExecutor.replan(game, store(state), fn fresh ->
              initialized =
                TijaraTides.UseCases.CommitPreparation.prepare(
                  fresh,
                  TijaraTides.UseCases.LotAllocation.run(
                    fresh,
                    store(state),
                    &Game.initialize(&1, state.catalogue)
                  )
                )

              # Initial market creation may take longer than an ordinary gameplay call.
              case GameStore.commit(repo, state.world_id, fresh.epoch, fresh, initialized, nil,
                     timeout: 120_000
                   ) do
                {:ok, :ok} ->
                  TijaraTides.UseCases.CommitExecutor.outcome(
                    TijaraTides.UseCases.CommitPreparation.accepted(initialized),
                    %{},
                    true
                  )

                {:error, reason} ->
                  {:halt, reason}
              end
            end)

          case result do
            {:ok, outcome} -> {:ok, accept_game(%{state | status: :ready}, outcome.game)}
            _ -> {:ok, %{state | status: :unavailable}}
          end
        end,
        fn _ -> {:ok, OperationBoundary.pause(state)} end
      )
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_call({:report_plan, token, selection}, _from, state) do
    OperationBoundary.run(
      :report_plan,
      fn ->
        result =
          if state.status == :ready do
            plan =
              TijaraTides.UseCases.ReportQueries.plan(
                state.game,
                hash(token),
                System.system_time(:millisecond),
                selection
              )

            {:ok, plan, {ReportStore, %{repo: state.repo, world_id: state.world_id}}}
          else
            {:error, :unavailable}
          end

        {:reply, result, state}
      end,
      fn _ -> {:reply, {:error, :report_unavailable}, state} end
    )
  end

  @impl true
  def handle_call(:readiness, _from, state), do: {:reply, state.status, state}

  def handle_call({:snapshot, token}, from, state) do
    # Reads are the owner's highest-frequency work, so they are measured with one bare
    # event: no correlation identifier, no start event and no log line, each of which
    # would cost more than the snapshot on this path. See UseCases.GameQueries.snapshot.
    started = System.monotonic_time()

    view =
      if state.status == :ready do
        TijaraTides.UseCases.GameQueries.snapshot(
          state.game,
          state.catalogue,
          state.projection,
          hash(token),
          state.wall_clock.()
        )
      else
        %{status: state.status, public: nil, private: nil, markets: %{}}
      end

    built = System.monotonic_time()

    # Building the view is cheap because it shares structure with the owner's heap. The
    # term is flattened into the caller's heap when it is sent, and the owner pays for
    # that: on a large world it costs several times the build. Returning {:reply, view,
    # state} would leave that copy outside the callback where no span can see it, so the
    # reply is sent here instead. It is the same send, only somewhere it can be timed.
    GenServer.reply(from, view)

    :telemetry.execute(
      [:tijara_tides, :snapshot],
      %{duration: built - started, reply: System.monotonic_time() - built},
      %{}
    )

    {:noreply, state}
  end

  def handle_call({:preview, token, id, destination}, _from, %{status: :ready} = state) do
    result =
      TijaraTides.UseCases.GameQueries.preview(
        state.game,
        state.catalogue,
        hash(token),
        state.wall_clock.(),
        id,
        destination
      )

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
                 tick_due_mono: System.monotonic_time(:millisecond) + state.tick_ms,
                 timer: :erlang.start_timer(state.tick_ms, self(), :tick)
             }}

      _ ->
        {:reply, {:error, :invalid_session}, state}
    end
  end

  def handle_call(:seed, _from, %{status: :ready} = state) do
    code = token()

    lifecycle(state, {:seed, hash(code)}, context(state), fn _ -> {:ok, code} end)
  end

  def handle_call(
        {:email_request, token, purpose, address, request_id, requester},
        _from,
        %{status: :ready} = state
      )
      when is_binary(request_id) and byte_size(request_id) in 1..128 and is_binary(requester) and
             byte_size(requester) <= 128 and is_binary(address) and byte_size(address) <= 254 and
             purpose in ["login", "link", "invite"] do
    context = context(state)

    id =
      hash(
        :erlang.term_to_binary(
          {state.world_id, hash(token), requester, purpose, address, request_id}
        )
      )

    ctx =
      Map.merge(context, %{
        id: id,
        hash: hash(email_token(id)),
        requester: hash(requester)
      })

    lifecycle(state, {:email_request, hash(token), purpose, address}, ctx)
  end

  def handle_call({:email_request, _, _, _, _, _}, _from, %{status: :ready} = state),
    do: {:reply, {:error, :email_invalid}, state}

  def handle_call({:email_redeem, code, device, signed_in}, _from, %{status: :ready} = state)
      when is_binary(code) and byte_size(code) == 43 and is_binary(device) and
             byte_size(device) == 43 do
    lifecycle(
      state,
      {:email_redeem, hash(code), hash(device), hash(signed_in)},
      context(state),
      fn _ -> {:ok, %{"session" => device}} end
    )
  end

  def handle_call({:email_redeem, _, _, _}, _from, %{status: :ready} = state),
    do: {:reply, {:error, :email_link_invalid}, state}

  def handle_call(:email_pending, _from, %{status: :ready} = state) do
    now = System.system_time(:millisecond)

    rows =
      Game.entities(state.game, "email_requests")
      |> Map.values()
      |> Enum.filter(
        &(&1["delivery"] == "pending" and &1["retry_ms"] <= now and &1["used_session"] == nil and
            &1["expires_ms"] > if(&1["purpose"] == "invite", do: state.game.clock_ms, else: now))
      )
      |> Enum.sort_by(& &1["created_ms"])
      |> Enum.take(1)
      |> Enum.map(
        &Map.put(
          &1,
          "locale",
          get_in(state.game, [:entities, "accounts", &1["account_id"], "locale"]) || "en"
        )
      )

    {:reply, rows, state}
  end

  def handle_call({action, id}, _from, %{status: :ready} = state)
      when action in [:email_failed, :email_delivered] do
    lifecycle(state, {action, id}, context(state), fn _ -> :ok end)
  end

  def handle_call({:redeem, code, session}, _from, %{status: :ready} = state)
      when is_binary(code) and byte_size(code) <= 100 and
             is_binary(session) and byte_size(session) == 43 do
    lifecycle(
      state,
      {:redeem, hash(String.trim(code)), hash(session)},
      context(state),
      fn result -> {:ok, Map.put(result, "session", session)} end
    )
  end

  def handle_call({:sign_out, token}, _from, %{status: :ready} = state) do
    lifecycle(state, {:sign_out, hash(token)}, context(state), fn _ -> :ok end)
  end

  def handle_call({:command, token, request, command}, _from, %{status: :ready} = state)
      when is_binary(request) and byte_size(request) in 1..128 and is_map(command) do
    request = %TijaraTides.UseCases.CommandRequest{
      id: request,
      payload: command,
      fingerprint: hash(:erlang.term_to_binary(command))
    }

    invitation = fn account_id, request_id ->
      invite =
        :crypto.mac(:hmac, :sha256, invite_key(), "invite:" <> account_id <> ":" <> request_id)
        |> Base.url_encode64(padding: false)

      decorate = fn result ->
        if command["action"] == "invite" do
          code =
            if result["invitation"] == hash(invite),
              do: invite,
              else: legacy_invite(account_id, request_id)

          Map.put(result, "code", code)
        else
          result
        end
      end

      %{hash: hash(invite), decorate: decorate}
    end

    OperationBoundary.call(
      :command,
      state,
      fn ->
        TijaraTides.UseCases.GameCommands.run(
          state.game,
          hash(token),
          request,
          context(state),
          store(state),
          invitation
        )
      end,
      &accept_outcome/2,
      &refresh_game/2
    )
  end

  def handle_call(_request, _from, state), do: {:reply, {:error, state.status}, state}

  @impl true
  def handle_info({:timeout, timer, :tick}, %{timer: timer} = state),
    do: handle_info(:tick, state)

  def handle_info(:tick, %{status: :ready, active: true} = state) do
    OperationBoundary.run(
      :progression,
      fn ->
        now = System.monotonic_time(:millisecond)
        TijaraTides.Infrastructure.Measurements.tick_lag(state.tick_due_mono, now)
        elapsed = max(0, now - state.last_mono)

        case TijaraTides.UseCases.LifecycleCommands.run(
               state.game,
               {:advance, elapsed},
               context(state),
               store(state)
             ) do
          {:ok, outcome} ->
            next = accept_outcome(state, outcome)
            if state.timer, do: Process.cancel_timer(state.timer)

            {:noreply, %{schedule_tick(next, now) | last_mono: now}}

          {:error, :market_busy, fresh} ->
            next = refresh_game(state, fresh)
            if state.timer, do: Process.cancel_timer(state.timer)
            {:noreply, schedule_tick(next, now)}

          {:halt, reason} ->
            Logger.error("World progression paused: #{reason}")
            {:noreply, OperationBoundary.pause(state)}
        end
      end,
      fn _ -> {:noreply, OperationBoundary.pause(state)} end
    )
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp schedule_tick(state, started) do
    finished = System.monotonic_time(:millisecond)
    lag = if state.tick_due_mono, do: max(0, started - state.tick_due_mono), else: 0

    schedule =
      TijaraTides.Infrastructure.TickSchedule.sample(state.tick_schedule, finished - started, lag)

    %{
      state
      | tick_schedule: schedule,
        tick_ms: schedule.interval,
        tick_due_mono: finished + schedule.interval,
        timer: :erlang.start_timer(schedule.interval, self(), :tick)
    }
  end

  defp context(state),
    do: %{
      id: request_id(),
      auction_seed: request_id(),
      wall_ms: state.wall_clock.(),
      catalogue: state.catalogue
    }

  defp account(state, token),
    do: TijaraTides.UseCases.Authentication.required(state.game, hash(token), state.wall_clock.())

  defp legacy_invite(account_id, request) do
    :crypto.mac(
      :hmac,
      :sha256,
      Application.fetch_env!(:tijara_tides, :game_secret),
      "invite:" <> account_id <> ":" <> request
    )
    |> Base.url_encode64(padding: false)
  end

  defp invite_key,
    do:
      :crypto.mac(
        :hmac,
        :sha256,
        Application.fetch_env!(:tijara_tides, :game_secret),
        "tijara-tides/invite-key/v1"
      )

  defp store(state),
    do:
      {TijaraTides.Infrastructure.Persistence.CommandStore,
       %{repo: state.repo, world_id: state.world_id}}

  defp lifecycle(state, operation, context, reply \\ &{:ok, &1}) do
    OperationBoundary.call(
      :lifecycle,
      state,
      fn ->
        TijaraTides.UseCases.LifecycleCommands.run(state.game, operation, context, store(state))
      end,
      &accept_outcome/2,
      &refresh_game/2,
      reply
    )
  end

  defp accept_outcome(state, %{committed?: false, refreshed?: true, game: game}),
    do: refresh_game(state, game)

  defp accept_outcome(state, %{committed?: false}), do: state

  defp accept_outcome(state, outcome) do
    next =
      if outcome.refreshed?,
        do: refresh_game(state, outcome.game),
        else: accept_game(state, outcome.game)

    unless outcome.refreshed?,
      do:
        Phoenix.PubSub.broadcast(
          TijaraTides.PubSub,
          @topic,
          {:game_changed, outcome.game.revision}
        )

    next
  end

  defp refresh_game(state, game) do
    elapsed = max(0, game.clock_ms - state.game.clock_ms)
    next = accept_game(state, game)
    Phoenix.PubSub.broadcast(TijaraTides.PubSub, @topic, {:game_changed, game.revision})
    %{next | last_mono: min(System.monotonic_time(:millisecond), state.last_mono + elapsed)}
  end

  defp accept_game(state, game) do
    projection = TijaraTides.UseCases.WorldProjection.build(game, state.catalogue)
    %{state | game: game, projection: projection}
  end
end
