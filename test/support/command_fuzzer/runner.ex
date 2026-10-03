defmodule TijaraTides.CommandFuzzer.Runner do
  @moduledoc "Shared dependency-aware replay. Preconditions skip invalid shrink actions; failures always propagate."
  import ExUnit.Assertions
  alias TijaraTides.CommandFuzzer.{Scenarios, Specs, Artifacts}
  alias TijaraTides.Domain.{Game, ReadState}

  def pure(family, parameters, suffix, opts \\ []) do
    {game, catalogue} = TijaraTides.CommandFuzzer.fixture()

    b = %{
      a: "account",
      company_a: "company",
      ship: "company:1",
      ship_two: "company:2",
      b_session: "other-session",
      beneficiary_session: "beneficiary-session"
    }

    {game, catalogue, b} = Scenarios.fixture(game, catalogue, b, family)

    backend = %{
      kind: :pure,
      command: &pure_command/5,
      tick: &pure_tick/3,
      observe: fn game, _, _ -> game end,
      replay: fn game, _, _, _ -> game end,
      restart: fn game, _, _ -> game end
    }

    replay(
      game,
      catalogue,
      b,
      Map.merge(backend, Keyword.get(opts, :backend, %{})),
      family,
      parameters,
      suffix,
      opts
    )
  end

  def replay(game, catalogue, bindings, backend, family, parameters, suffix, opts \\ []) do
    prefix =
      if family == :broad, do: Specs.broad_prefix(), else: Scenarios.prefix(family, parameters)

    limit = Keyword.get(opts, :limit, 30)
    assert length(prefix) + length(suffix) <= limit, "trace exceeds #{limit} actions"

    model = %{
      loan: nil,
      loan_ms: nil,
      clock_ms: game.clock_ms,
      debts: %{},
      pending: false,
      ship_status: "docked",
      queued_status: "docked",
      port: "Jakarta",
      cargo: 0,
      stored: 0,
      warehouse: false,
      preset: false,
      rule: false,
      route: nil,
      active: true,
      ship_deadline: nil,
      destination: nil,
      milestones: MapSet.new(),
      origin_amount: parameters.amount,
      initial_reserved: game.entities["companies"][bindings.company_a]["reserved"]
    }

    r = %{
      game: game,
      catalogue: catalogue,
      b: bindings,
      model: model,
      backend: backend,
      family: family,
      parameters: parameters,
      trace: [],
      suffix: suffix,
      last: nil,
      index: 0,
      stats: %{
        generated: length(prefix) + length(suffix),
        attempted: 0,
        accepted: 0,
        expected_rejected: 0,
        skipped: 0,
        harness: 0
      },
      artifact: Keyword.get(opts, :artifact, "#{family}-#{ExUnit.configuration()[:seed]}")
    }

    # The prefix is outside StreamData's shrinkable suffix and guarantees progress.
    try do
      r = Enum.reduce(prefix, r, &step(&2, &1, true))

      required =
        if family == :broad,
          do: [:debt_acquired, :debt_released],
          else: Scenarios.milestones(family)

      assert Enum.all?(required, &MapSet.member?(r.model.milestones, &1)),
             "Missing #{inspect(required -- MapSet.to_list(r.model.milestones))} milestones"

      assert r.stats.accepted >= 5,
             "prefix made insufficient command progress: #{inspect(r.stats)}"

      r = Enum.reduce(suffix, r, &step(&2, &1, false))
      Artifacts.success(r)
      r
    rescue
      error ->
        unless Process.delete({__MODULE__, :archived}),
          do: Artifacts.failure(r, %{op: :progress}, error, __STACKTRACE__)

        reraise error, __STACKTRACE__
    end
  end

  defp step(r, action, essential?) do
    r = %{r | index: r.index + 1}

    if Specs.eligible?(action, r.model) and
         not (r.backend.kind == :pure and action.op in [:replay, :restart]) do
      try do
        Process.put({__MODULE__, :failure_context}, r)
        apply_step(r, action)
      rescue
        error ->
          # Archive before reraising into StreamData. Never turn assertions into skips.
          Artifacts.failure(
            Process.get({__MODULE__, :failure_context}, r),
            action,
            error,
            __STACKTRACE__
          )

          Process.put({__MODULE__, :archived}, true)
          reraise error, __STACKTRACE__
      after
        Process.delete({__MODULE__, :failure_context})
      end
    else
      assert not essential?, "Essential action lost its prerequisite: #{inspect(action)}"

      %{
        r
        | stats: Map.update!(r.stats, :skipped, &(&1 + 1)),
          trace: r.trace ++ [%{symbolic: action, outcome: :skipped, clock_ms: r.game.clock_ms}]
      }
    end
  end

  defp apply_step(r, %{op: :command} = action) do
    payload = Specs.payload(action, r.b)
    id = "trace:#{r.index}"
    before = r.game
    actor = Map.fetch!(r.b, action.actor)
    outcome = r.backend.command.(before, r.catalogue, actor, payload, id)
    r = %{r | stats: Map.update!(r.stats, :attempted, &(&1 + 1))}

    Process.put({__MODULE__, :failure_context}, %{
      r
      | trace:
          r.trace ++
            [
              %{
                symbolic: action,
                resolved: payload,
                outcome: outcome_tag(outcome),
                clock_ms: before.clock_ms
              }
            ]
    })

    case outcome do
      {:ok, game, reply} ->
        assert action.expected == :ok,
               "Expected rejection #{inspect(action.expected)}: #{inspect(payload)}"

        b = bind(r.b, action, before, game, reply)
        model = postcondition!(r.model, action, before, game, r.b, b, payload)

        r = %{
          r
          | game: game,
            b: b,
            model: model,
            last: %{actor: actor, payload: payload, id: id, reply: reply},
            stats: Map.update!(r.stats, :accepted, &(&1 + 1))
        }

        checked(r, action, payload, reply)

      {:error, reason} ->
        TijaraTides.CommandFuzzer.outcome!(outcome)
        actual = if is_tuple(reason), do: elem(reason, 0), else: reason

        assert action.expected == actual,
               "Model-valid command rejected: expected #{inspect(action.expected)}, got #{inspect(reason)} for #{inspect(payload)}"

        assert r.backend.observe.(before, r.catalogue, r.b).entities == before.entities

        checked(
          %{r | stats: Map.update!(r.stats, :expected_rejected, &(&1 + 1))},
          action,
          payload,
          outcome
        )

      other ->
        TijaraTides.CommandFuzzer.outcome!(other)
    end
  end

  defp apply_step(r, %{op: :tick} = action) do
    elapsed = elapsed(r, action.target)
    assert elapsed >= 0, "negative symbolic clock advance"
    game = r.backend.tick.(r.game, r.catalogue, elapsed)
    assert game.clock_ms == r.game.clock_ms + elapsed, "tick clock drift"
    model = tick_model(r.model, r.game, game, r.b) |> Map.put(:clock_ms, game.clock_ms)
    model = invariant!(model, action.invariant, r, game)

    checked(
      %{r | game: game, model: model, stats: Map.update!(r.stats, :harness, &(&1 + 1))},
      action,
      %{elapsed: elapsed},
      :ok
    )
  end

  defp apply_step(r, %{op: :observe} = action) do
    game = r.backend.observe.(r.game, r.catalogue, r.b)
    assert game.entities == r.game.entities
    public = Game.public(game, r.catalogue)
    refute inspect(public) =~ "protected-instruction"

    for key <- ~w(remote_links visit_budgets departure_requests route_rules),
        do: refute(Map.has_key?(public, key))

    checked(%{r | stats: Map.update!(r.stats, :harness, &(&1 + 1))}, action, %{}, :ok)
  end

  defp apply_step(r, %{op: :replay} = action) do
    game = if r.last, do: r.backend.replay.(r.game, r.catalogue, r.b, r.last), else: r.game
    assert game.entities == r.game.entities
    checked(%{r | stats: Map.update!(r.stats, :harness, &(&1 + 1))}, action, %{}, :ok)
  end

  defp apply_step(r, %{op: :restart} = action) do
    game = r.backend.restart.(r.game, r.catalogue, r.b)
    # SQL restart may evict optional codec fields; backend proves targeted equality.
    checked(%{r | game: game, stats: Map.update!(r.stats, :harness, &(&1 + 1))}, action, %{}, :ok)
  end

  defp checked(r, action, resolved, outcome) do
    Process.put({__MODULE__, :failure_context}, %{
      r
      | trace:
          r.trace ++
            [
              %{
                symbolic: action,
                resolved: resolved,
                outcome: outcome,
                clock_ms: r.game.clock_ms,
                revision: r.game.revision
              }
            ]
    })

    assert_world!(r.game, r.catalogue)

    %{
      r
      | trace:
          r.trace ++
            [
              %{
                symbolic: action,
                resolved: resolved,
                outcome: outcome,
                clock_ms: r.game.clock_ms,
                revision: r.game.revision,
                bindings: r.b
              }
            ]
    }
  end

  def assert_world!(game, catalogue) do
    rows = fn table -> Map.values(Map.get(game.entities, table, %{})) end

    for company <- rows.("companies") do
      assert company["cash"] >= company["reserved"] and company["reserved"] >= 0
      owner = company["id"]

      sum = fn table, field, predicate ->
        Enum.sum(
          for row <- rows.(table), row["company_id"] == owner, predicate.(row), do: row[field]
        )
      end

      promised =
        sum.("visit_budgets", "remaining", fn _ -> true end) +
          sum.("departure_requests", "accumulated", fn _ -> true end) +
          sum.("warehouse_liquidations", "proceeds", &(&1["status"] != "completed")) +
          Enum.sum(
            for ship <- rows.("ships"),
                ship["company_id"] == owner and ship["status"] == "sailing",
                do: ship["fuel_total"] - ship["fuel_burned"]
          ) +
          Enum.sum(
            for order <- rows.("exchange_orders"),
                order["company_id"] == owner and order["side"] == "buy",
                do: order["quantity"] * order["price"]
          ) +
          sum.("auction_bids", "amount", fn bid ->
            game.entities["auctions"][bid["auction_id"]]["status"] == "scheduled"
          end)

      assert company["reserved"] == promised,
             "reservation conservation for #{owner}: #{company["reserved"]} vs #{promised}"

      active =
        for row <- rows.("departure_requests"),
            row["company_id"] == owner and row["window_deadline_ms"] != nil,
            do: row

      assert length(active) <= 1, "multiple accumulator windows"
    end

    for ship <- rows.("ships") do
      spec = Game.classes()[ship["class"]]

      weight =
        Enum.sum(
          for batch <- ship["cargo"],
              do: batch["quantity"] * catalogue["goods"][batch["good"]]["weight_kg"]
        )

      volume =
        Enum.sum(
          for batch <- ship["cargo"],
              do: batch["quantity"] * catalogue["goods"][batch["good"]]["volume_l"]
        )

      assert weight <= spec["weight"] and volume <= spec["volume"], "physical capacity"
      assert ship["fuel_burned"] in 0..ship["fuel_total"]
      assert Enum.all?(ship["cargo"], &(&1["quantity"] > 0))
    end

    for warehouse <- rows.("warehouses") do
      volume =
        Enum.sum(
          for batch <- warehouse["cargo"],
              do: batch["quantity"] * catalogue["goods"][batch["good"]]["volume_l"]
        )

      assert volume <= warehouse["blocks"] * 100_000, "warehouse physical capacity"
    end

    for budget <- rows.("visit_budgets") do
      assert budget["remaining"] in 0..budget["amount"]

      if budget["stop_id"] do
        route = game.entities["ship_routes"][budget["ship_id"]]
        assert route["visit"] == budget["visit"], "stale visit identity"
      end
    end

    for event <- Map.get(game, :journal, []) do
      assert Enum.sum(Enum.map(event.entries, &elem(&1, 1))) == 0, "unbalanced journal"
    end

    for pool <- rows.("warehouse_liquidations") do
      assert pool["occupied_blocks"] <= pool["original_blocks"]
      assert pool["charged"] <= pool["proceeds"]
      if pool["status"] == "completed", do: assert(game.entities["warehouses"][pool["id"]] == nil)
    end

    :ok
  end

  defp bind(b, %{as: nil}, _, _, _), do: b

  defp bind(b, action, before, game, reply) do
    table =
      case action.spec do
        :add_stop -> "route_stops"
        :add_rule -> "route_rules"
        :warehouse_lease -> "warehouses"
        :borrow -> "loans"
        :company -> "companies"
        :guarantee -> "guarantees"
        :preset_save -> "markdown_presets"
        :purchase_ship -> "ships"
        _ -> nil
      end

    if table do
      added =
        Map.keys(Map.get(game.entities, table, %{})) --
          Map.keys(Map.get(before.entities, table, %{}))

      assert [id] = added,
             "symbol #{inspect(action.as)} did not acquire one identity: #{inspect(reply)}"

      Map.put(b, action.as, id)
    else
      b
    end
  end

  defp postcondition!(m, action, before, after_state, b, next_b, payload) do
    actor = Map.fetch!(b, action.actor)
    co_id = before.entities["accounts"][actor]["company_id"]
    old = before.entities["companies"][co_id]
    new_co_id = after_state.entities["accounts"][actor]["company_id"] || co_id
    new = after_state.entities["companies"][new_co_id]
    spec = action.spec

    m =
      case spec do
        :borrow ->
          assert new["cash"] == old["cash"] + payload["amount"]
          assert new["profit"] == old["profit"]
          assert after_state.entities["loans"][next_b.loan]["remaining"] == payload["amount"]

          m
          |> Map.put(:loan, if(action.actor == :a, do: next_b.loan, else: m.loan))
          |> Map.put(:loan_ms, after_state.clock_ms)
          |> put_in([:debts, next_b.loan], payload["amount"])
          |> mark(:debt_acquired)

        :recast ->
          prior = Map.fetch!(m.debts, b.loan)
          interest = before.entities["loans"][b.loan]["interest_accrued"]

          assert after_state.entities["loans"][b.loan]["remaining"] ==
                   prior - payload["amount"] + interest

          assert new["cash"] == old["cash"] - payload["amount"]

          m
          |> put_in([:debts, b.loan], prior - payload["amount"] + interest)
          |> mark(:partial_payment)

        :repay ->
          debt = before.entities["loans"][b.loan]

          assert new["cash"] ==
                   old["cash"] - debt["remaining"] - debt["interest_due"] -
                     debt["interest_accrued"]

          assert after_state.entities["loans"][b.loan]["remaining"] == 0
          assert after_state.entities["loans"][b.loan]["status"] == "repaid"

          m
          |> Map.put(:loan, if(action.actor == :a, do: nil, else: m.loan))
          |> mark(:debt_released)

        :guarantee ->
          assert new["cash"] == old["cash"] - 5_000_000
          assert after_state.entities["guarantees"][next_b.guarantee]["amount"] == 5_000_000
          mark(m, :escrow_acquired)

        :bankruptcy ->
          assert after_state.entities["companies"][co_id]["bankruptcy_ms"] != nil
          if action.actor == :a, do: %{m | active: false}, else: m

        :company ->
          assert new["cash"] == 0
          m

        :purchase_ship ->
          assert new["cash"] == old["cash"] - 4_000_000
          m

        :preset_save ->
          assert after_state.entities["markdown_presets"][next_b.preset]["account_id"] == actor
          %{m | preset: true}

        :preset_delete ->
          assert after_state.entities["markdown_presets"][b.preset] == nil,
                 "preset lifetime: deletion retained an owned preset"

          %{m | preset: false}

        :rename_ship ->
          assert after_state.entities["ships"][b.ship]["name"] == payload["name"]
          m

        :buy ->
          ship = after_state.entities["ships"][b.ship]
          assert ship["status"] == "loading"
          assert cargo(ship) == m.cargo + payload["quantity"]

          %{
            m
            | cargo: m.cargo + payload["quantity"],
              ship_status: "loading",
              ship_deadline: ship["arrive_ms"]
          }

        :queued_buy ->
          assert after_state.entities["ships"][b.ship_two]["pending_side"] == "buy"
          assert new["cash"] == old["cash"]
          mark(%{m | pending: true}, :queued)

        :cancel_berth_trade ->
          assert after_state.entities["ships"][b.ship_two]["pending_side"] == nil
          assert new["cash"] == old["cash"]
          mark(%{m | pending: false}, :cancelled_queue)

        :sell ->
          assert cargo(after_state.entities["ships"][b.ship]) == m.cargo - payload["quantity"]

          %{
            m
            | cargo: m.cargo - payload["quantity"],
              ship_status: "unloading",
              ship_deadline: after_state.entities["ships"][b.ship]["arrive_ms"]
          }

        :sail ->
          ship = after_state.entities["ships"][b.ship]
          assert ship["status"] == "sailing" and ship["destination"] == payload["destination"]
          assert ship["cargo"] == before.entities["ships"][b.ship]["cargo"]

          if m.route do
            departing = if m.port == "Jakarta", do: b.origin, else: b.destination

            assert after_state.entities["visit_budgets"][departing] == nil,
                   "departing budget leaked"
          end

          mark(
            %{
              m
              | ship_status: "sailing",
                ship_deadline: ship["arrive_ms"],
                destination: ship["destination"]
            },
            :budget_released
          )

        :reroute ->
          ship = after_state.entities["ships"][b.ship]
          assert new["cash"] == old["cash"], "reroute spent already settled fuel"
          assert ship["cargo"] == before.entities["ships"][b.ship]["cargo"]

          mark(
            %{m | destination: payload["destination"], ship_deadline: ship["arrive_ms"]},
            :rerouted
          )

        :warehouse_lease ->
          assert after_state.entities["warehouses"][next_b.warehouse]["blocks"] ==
                   payload["blocks"]

          %{m | warehouse: true}

        :warehouse_store ->
          assert cargo(after_state.entities["ships"][b.ship]) == m.cargo - payload["quantity"]

          mark(
            %{
              m
              | cargo: m.cargo - payload["quantity"],
                stored: m.stored + payload["quantity"],
                ship_status: "unloading",
                ship_deadline: after_state.entities["ships"][b.ship]["arrive_ms"]
            },
            :stored
          )

        :warehouse_release ->
          assert after_state.entities["warehouses"][b.warehouse] == nil
          %{m | warehouse: false}

        :add_rule ->
          %{m | rule: true}

        :remove_rule ->
          %{m | rule: false}

        :start ->
          mark(%{m | route: :running}, :budget_acquired)

        :pause ->
          %{m | route: :paused}

        :resume ->
          %{m | route: :running}

        _ ->
          m
      end

    m
  end

  defp tick_model(m, _before, game, b) do
    if m.ship_deadline && game.clock_ms >= m.ship_deadline && m.active do
      ship = game.entities["ships"][b.ship]
      assert ship["status"] == "docked"
      port = if m.ship_status == "sailing", do: m.destination, else: m.port
      assert ship["port"] == port
      assert cargo(ship) == m.cargo
      %{m | ship_status: "docked", port: port, ship_deadline: nil}
    else
      m
    end
  end

  defp invariant!(m, nil, _, _), do: m

  defp invariant!(m, :queue_progress, r, game) do
    ship = game.entities["ships"][r.b.ship_two]
    assert ship["status"] == "loading" and ship["pending_side"] == nil
    assert cargo(ship) == r.parameters.quantity
    mark(%{m | pending: false, queued_status: "loading"}, :queue_progress)
  end

  defp invariant!(m, :return_port, r, game) do
    assert game.entities["ships"][r.b.ship]["port"] == "Jakarta"
    mark(m, :return_port)
  end

  defp invariant!(m, :return_visit, r, game) do
    row = game.entities["visit_budgets"][r.b.origin]
    assert row["remaining"] == r.parameters.amount and row["visit"] == 2
    assert game.entities["ships"][r.b.ship]["port"] == "Jakarta"
    mark(m, :return_visit)
  end

  defp invariant!(m, op, r, game) when op in [:guarantee_release, :guarantee_claim] do
    g = game.entities["guarantees"][r.b.guarantee]
    loss = if op == :guarantee_claim, do: 4_000_000, else: 0
    assert g["forfeited"] == loss
    assert g["status"] == if(loss == 0, do: "released", else: "claimed")
    assert game.entities["companies"][r.b.company_a]["cash"] == 8_000_000 - loss
    mark(m, :escrow_settled)
  end

  defp invariant!(m, op, r, game)
       when op in [:before_grace, :liquidating, :liquidation_complete] do
    pool = game.entities["warehouse_liquidations"][r.b.warehouse]

    status =
      %{before_grace: "grace", liquidating: "liquidating", liquidation_complete: "completed"}[op]

    assert pool["status"] == status
    assert pool["grace_end_ms"] == pool["expires_ms"] + 43_200_000

    if op == :liquidation_complete do
      assert game.entities["warehouses"][r.b.warehouse] == nil

      expected =
        div(r.catalogue["goods"]["lumber"]["reference_cents"] * r.parameters.quantity, 10)

      assert pool["proceeds"] == expected
      assert pool["paid"] == 0 and pool["sunk"] == pool["proceeds"] - pool["charged"]
    end

    mark(m, if(op == :before_grace, do: :grace, else: op))
  end

  defp elapsed(_r, value) when is_integer(value), do: value
  defp elapsed(r, {:arrival, _}), do: max(0, r.model.ship_deadline - r.game.clock_ms)

  defp elapsed(r, {:fraction, _, divisor}),
    do: div(r.model.ship_deadline - r.game.clock_ms, divisor)

  defp elapsed(r, {:lease_expiry, offset}),
    do: r.game.entities["warehouses"][r.b.warehouse]["expires_ms"] + offset - r.game.clock_ms

  defp elapsed(r, {:grace_end, offset}),
    do:
      r.game.entities["warehouse_liquidations"][r.b.warehouse]["grace_end_ms"] + offset -
        r.game.clock_ms

  defp elapsed(r, {:auction_close, offset}) do
    closes =
      for {_, a} <- r.game.entities["auctions"],
          a["liquidation_id"] == r.b.warehouse,
          do: a["closes_ms"]

    assert closes != [], "never reached liquidation auction"
    Enum.max(closes) + offset - r.game.clock_ms
  end

  defp mark(m, milestone), do: %{m | milestones: MapSet.put(m.milestones, milestone)}

  defp cargo(ship),
    do: Enum.sum(for batch <- ship["cargo"], batch["good"] == "lumber", do: batch["quantity"])

  defp outcome_tag({:ok, _game, reply}), do: {:ok, reply}
  defp outcome_tag(outcome), do: outcome

  defp pure_command(game, catalogue, actor, payload, id) do
    game = allocate(game, id)

    TijaraTides.UseCases.GameCommands.execute(
      game,
      ReadState.get(game, "accounts", actor),
      payload,
      %{id: id, wall_ms: 1, catalogue: catalogue, auction_seed: "fuzzer-valuation-v1"}
    )
  end

  defp pure_tick(game, catalogue, elapsed),
    do: Game.advance(allocate(game, "tick:#{game.clock_ms}:#{elapsed}"), elapsed, catalogue)

  defp allocate(game, id),
    do: Map.put(game, :lot_allocation, Enum.map(1..1024, &"fuzz-lot:#{id}:#{&1}"))
end
