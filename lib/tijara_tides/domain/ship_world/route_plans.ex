defmodule TijaraTides.Domain.ShipWorld.RoutePlans do
  @moduledoc "Private repeating stop templates and their current visit. Execution uses ordinary ship instructions."
  import TijaraTides.Domain.State, except: [get: 3, put: 4]
  alias TijaraTides.Domain.State
  alias TijaraTides.Domain.Ship.{RouteHeader, RouteStop, RouteTarget, VisitPlan}
  alias TijaraTides.Domain.{CargoRules, Notices}
  @open ["planned", "waiting"]

  defp get(state, "ship_routes", id),
    do: State.get(state, "ship_routes", id) |> RouteHeader.from_row()

  defp get(state, "route_stops", id),
    do: State.get(state, "route_stops", id) |> RouteStop.from_row()

  defp get(state, "route_rules", id),
    do: State.get(state, "route_rules", id) |> RouteTarget.from_row()

  defp get(state, "visit_plans", id),
    do: State.get(state, "visit_plans", id) |> VisitPlan.from_row()

  defp get(state, kind, id), do: State.get(state, kind, id)

  defp put(state, "ship_routes", id, value),
    do:
      State.put(state, "ship_routes", id, value |> RouteHeader.from_row() |> RouteHeader.to_row())

  defp put(state, "route_stops", id, value),
    do: State.put(state, "route_stops", id, value |> RouteStop.from_row() |> RouteStop.to_row())

  defp put(state, "route_rules", id, value),
    do:
      State.put(state, "route_rules", id, value |> RouteTarget.from_row() |> RouteTarget.to_row())

  defp put(state, "visit_plans", id, value),
    do: State.put(state, "visit_plans", id, value |> VisitPlan.from_row() |> VisitPlan.to_row())

  defp put(state, kind, id, row), do: State.put(state, kind, id, row)

  @doc "Update an uncommitted linked loading target and its current instruction together."
  def reconcile_linked_target(state, rule, catalogue) do
    route = get(state, "ship_routes", rule["ship_id"])
    stop = get(state, "route_stops", rule["stop_id"])
    ship = get(state, "ships", rule["ship_id"])

    if route && stop && route.cursor == stop.position && route.phase == "buying" &&
         not route.visit_finished && not route.wait_timed_out do
      order = get(state, "ship_instructions", "route:" <> rule["id"])

      next =
        Enum.at(stops(state, ship["id"]), rem(route.cursor + 1, length(stops(state, ship["id"]))))

      aboard =
        Enum.sum(
          for b <- ship["cargo"],
              b["good"] == rule["good"],
              CargoRules.qualifies?(b["expires_ms"], state.clock_ms, rule["min_remaining_ms"]),
              do: b["quantity"]
        )

      cond do
        order && (order["good"] != rule["good"] && order["filled"] > 0) ->
          {:error, :route_stop_committed}

        order && rule["budget"] != nil && rule["budget"] < order["spent"] ->
          {:error, :instruction_budget_invalid}

        order ->
          quantity = order["filled"] + max(0, rule["quantity"] - aboard)

          if quantity > 10_000 do
            {:error, :instruction_quantity_invalid}
          else
            changed = %{
              order
              | "quantity" => max(1, quantity),
                "limit" => rule["limit"],
                "budget" => rule["budget"],
                "min_remaining_ms" => rule["min_remaining_ms"],
                "good" => rule["good"],
                "status" => if(quantity <= order["filled"], do: "filled", else: "planned"),
                "reason" => "Route visit target"
            }

            {:ok, put(state, "ship_instructions", order["id"], changed)}
          end

        true ->
          {:ok, materialize(state, ship, stop, next, "buy", catalogue, true)}
      end
    else
      {:ok, state}
    end
  end

  def finish_current_visit(state, ship_id) do
    route = get(state, "ship_routes", ship_id)
    put(state, "ship_routes", ship_id, %{route | visit_finished: true})
  end

  def set_advance_budget(state, id, true, amount) do
    stop = get(state, "route_stops", id)
    put(state, "route_stops", id, %{stop | advance_budget: amount})
  end

  def set_advance_budget(state, id, false, amount) do
    plan = get(state, "visit_plans", id)
    put(state, "visit_plans", id, %{plan | advance_budget: amount})
  end

  def load(state, ship_id) do
    %TijaraTides.Domain.Ship.RoutePlan{
      header: get(state, "ship_routes", ship_id),
      stops: stops(state, ship_id),
      targets:
        entities(state, "route_rules")
        |> Map.values()
        |> Enum.filter(&(&1["ship_id"] == ship_id))
        |> Enum.map(&RouteTarget.from_row/1)
    }
  end

  def execute(state, account, params, context) do
    ship = get(state, "ships", params["ship"])
    company = get(state, "companies", account["company_id"])

    if is_nil(ship) or is_nil(company) or ship["company_id"] != company["id"] or
         company["bankruptcy_ms"] != nil do
      {:error, :route_ship_not_owned}
    else
      case edit(state, ship, params, context) do
        {:ok, changed, _} = result ->
          plan = load(changed, ship["id"])
          route = plan.header
          stops = plan.stops

          if route && route.status != "draft" &&
               (length(stops) < 2 or
                  Enum.any?(Enum.zip(stops, tl(stops) ++ [hd(stops)]), fn {a, b} ->
                    is_nil(context.catalogue["routes"][a.port <> "|" <> b.port])
                  end)), do: {:error, :route_needs_stops}, else: result

        error ->
          error
      end
    end
  end

  defp edit(state, ship, %{"operation" => "add_stop", "port" => port}, context) do
    route = get(state, "ship_routes", ship["id"])
    stops = stops(state, ship["id"])

    cond do
      route && route.status != "draft" && route.phase != "arrival" &&
          route.cursor == length(stops) - 1 ->
        {:error, :route_stop_committed}

      is_nil(route) and single_visit?(state, ship["id"]) ->
        {:error, :route_existing_instructions}

      length(stops) >= 8 ->
        {:error, :route_stop_limit}

      is_nil(context.catalogue["ports"][port]) or
          (stops != [] and List.last(stops).port == port) ->
        {:error, :route_port_invalid}

      true ->
        route =
          route ||
            %{
              "id" => ship["id"],
              "ship_id" => ship["id"],
              "company_id" => ship["company_id"],
              "status" => "draft",
              "cursor" => 0,
              "visit" => 0,
              "phase" => "arrival",
              "auto_depart" => true,
              "stop_after" => false,
              "reason" => "Add stops and cargo targets, then start the route"
            }

        route = RouteHeader.from_row(route)

        stop =
          RouteStop.from_row(%{
            "id" => context.id,
            "ship_id" => ship["id"],
            "company_id" => ship["company_id"],
            "position" => length(stops),
            "port" => port
          })

        {:ok, state |> put("ship_routes", ship["id"], route) |> put("route_stops", stop.id, stop),
         %{}}
    end
  end

  defp edit(state, ship, %{"operation" => operation} = p, context)
       when operation in ["add_rule", "update_rule"] do
    route = get(state, "ship_routes", ship["id"])
    stop = get(state, "route_stops", p["stop"])
    good = context.catalogue["goods"][p["good"]]
    existing = if operation == "update_rule", do: get(state, "route_rules", p["rule"])

    rules =
      Enum.reject(
        rules(state, p["stop"]),
        &(&1.id == p["rule"] and operation == "update_rule")
      )

    cond do
      is_nil(route) or
          (operation == "update_rule" and
             (is_nil(existing) or existing.ship_id != ship["id"] or
                existing.stop_id != p["stop"])) ->
        {:error, :route_edit_draft}

      is_nil(stop) or stop.ship_id != ship["id"] ->
        {:error, :route_port_invalid}

      is_nil(good) or good["manual"] != true or not CargoRules.compatible_class?(ship, good) or
          is_nil(get(state, "markets", stop.port <> "|" <> p["good"])) ->
        {:error, :instruction_cargo_invalid}

      p["side"] not in ["buy", "sell"] or
        Map.get(p, "quantity_mode", "fixed") not in ["fixed", "maximum"] or
        (Map.get(p, "quantity_mode", "fixed") == "fixed" and
           (not is_integer(p["quantity"]) or p["quantity"] not in 1..10_000)) or
        not is_integer(p["limit"]) or
          p["limit"] not in 0..1_000_000_000_000 ->
        {:error, :instruction_quantity_invalid}

      p["linked_warehouse_id"] not in [nil, ""] and
          (not is_binary(p["linked_warehouse_id"]) or p["side"] != "buy" or
             Map.get(p, "quantity_mode", "fixed") != "fixed" or p["limit"] == 0) ->
        {:error, :linked_order_invalid}

      p["side"] == "buy" and not is_nil(p["budget"]) and
          (not is_integer(p["budget"]) or p["budget"] not in 1..1_000_000_000_000) ->
        {:error, :instruction_budget_invalid}

      not CargoRules.valid_remaining?(Map.get(p, "min_remaining_ms", 0)) or
          (p["side"] != "buy" and Map.get(p, "min_remaining_ms", 0) != 0) ->
        {:error, :instruction_freshness_invalid}

      length(rules) >= 20 or
          Enum.any?(rules, &(&1.side == p["side"] and &1.good == p["good"])) ->
        {:error, :route_duplicate_rule}

      true ->
        rule =
          Map.take(p, ~w(side good quantity limit))
          |> Map.merge(%{
            "quantity_mode" => Map.get(p, "quantity_mode", "fixed"),
            "quantity" => if(p["quantity_mode"] == "maximum", do: nil, else: p["quantity"]),
            "id" => if(existing, do: existing.id, else: context.id),
            "ship_id" => ship["id"],
            "company_id" => ship["company_id"],
            "stop_id" => stop.id,
            "budget" => if(p["side"] == "buy", do: p["budget"]),
            "linked_warehouse_id" =>
              if(p["linked_warehouse_id"] in [nil, ""], do: nil, else: p["linked_warehouse_id"]),
            "min_remaining_ms" => Map.get(p, "min_remaining_ms", 0)
          })
          |> RouteTarget.from_row()

        {:ok, put(state, "route_rules", rule.id, rule), %{}}
    end
  end

  defp edit(state, ship, %{"operation" => "set_wait", "stop" => id} = p, _context) do
    stop = get(state, "route_stops", id)
    wait = p["max_wait_ms"]

    cond do
      is_nil(stop) or stop.ship_id != ship["id"] ->
        {:error, :route_port_invalid}

      not is_nil(wait) and
          (not is_integer(wait) or wait < 1 or wait > RouteStop.max_wait_ms()) ->
        {:error, :route_wait_invalid}

      true ->
        {:ok, put(state, "route_stops", id, %{stop | max_wait_ms: wait}), %{}}
    end
  end

  defp edit(state, ship, %{"operation" => "remove_rule", "rule" => id}, _context) do
    route = get(state, "ship_routes", ship["id"])
    rule = get(state, "route_rules", id)

    if route && rule && rule.ship_id == ship["id"],
      do: {:ok, delete(state, "route_rules", id), %{}},
      else: {:error, :route_edit_draft}
  end

  defp edit(state, ship, %{"operation" => "remove_stop", "stop" => id}, _context) do
    route = get(state, "ship_routes", ship["id"])
    stop = get(state, "route_stops", id)

    all = stops(state, ship["id"])
    current = if route, do: Enum.at(all, route.cursor)

    protected =
      if route && route.status != "draft",
        do: [route.cursor, rem(route.cursor + 1, length(all))],
        else: []

    if route && stop && stop.ship_id == ship["id"] do
      state =
        Enum.reduce(rules(state, id), state, &delete(&2, "route_rules", &1.id))
        |> delete("route_stops", id)

      state =
        stops(state, ship["id"])
        |> Enum.with_index()
        |> Enum.reduce(state, fn {s, n}, acc ->
          put(acc, "route_stops", s.id, %{s | position: n})
        end)

      state =
        cond do
          route.status != "draft" and stop.position in protected ->
            state
            |> clear_visit(ship["id"])
            |> put("ship_routes", route.id, %{
              route
              | status: "draft",
                cursor: 0,
                phase: "arrival",
                visit_finished: false,
                visit_arrived_ms: nil,
                wait_deadline_ms: nil,
                wait_timed_out: false,
                stop_after: false,
                reason: "Add stops and cargo targets, then start the route"
            })

          current && route.status != "draft" ->
            put(state, "ship_routes", route.id, %{
              route
              | cursor: get(state, "route_stops", current.id).position
            })

          true ->
            state
        end

      {:ok, state, %{}}
    else
      {:error, :route_stop_committed}
    end
  end

  defp edit(state, ship, %{"operation" => operation} = p, context) do
    route = get(state, "ship_routes", ship["id"])
    stops = stops(state, ship["id"])
    current = Enum.at(stops, if(route, do: route.cursor, else: 0))

    cond do
      is_nil(route) ->
        {:error, :route_missing}

      operation in ["start", "resume"] ->
        cond do
          length(stops) < 2 or hd(stops).port == List.last(stops).port ->
            {:error, :route_needs_stops}

          Map.get(p, "auto_depart", true) not in [true, false] ->
            {:error, :instruction_auto_depart_invalid}

          is_nil(current) or
              if(ship["status"] == "sailing", do: ship["destination"], else: ship["port"]) !=
                current.port ->
            {:error, :route_start_port}

          Enum.any?(Enum.zip(stops, tl(stops) ++ [hd(stops)]), fn {a, b} ->
            is_nil(context.catalogue["routes"][a.port <> "|" <> b.port])
          end) ->
            {:error, :route_port_invalid}

          true ->
            {:ok,
             put(state, "ship_routes", ship["id"], %{
               route
               | status: "running",
                 auto_depart: Map.get(p, "auto_depart", true),
                 stop_after: false,
                 reason:
                   if(route.wait_timed_out, do: "Maximum wait elapsed", else: "Following route")
             })
             |> arrived(ship["id"], state.clock_ms), %{}}
        end

      operation == "pause" ->
        {:ok, pause(state, route, "Paused by player; committed handling continues"), %{}}

      operation == "stop_after" and route.status == "running" ->
        {:ok, put(state, "ship_routes", ship["id"], %{route | stop_after: true}), %{}}

      operation == "delete" ->
        state = clear_visit(state, ship["id"])

        state =
          Enum.reduce(["route_rules", "route_stops", "ship_routes"], state, fn kind, acc ->
            Enum.reduce(entities(acc, kind), acc, fn {id, row}, acc ->
              if row["ship_id"] == ship["id"], do: delete(acc, kind, id), else: acc
            end)
          end)

        {:ok, state, %{}}

      true ->
        {:error, :unsupported_command}
    end
  end

  defp edit(_, _, _, _), do: {:error, :unsupported_command}

  def stops(state, ship),
    do:
      entities(state, "route_stops")
      |> Map.values()
      |> Enum.filter(&(&1["ship_id"] == ship))
      |> Enum.map(&RouteStop.from_row/1)
      |> Enum.sort_by(& &1.position)

  defp rules(state, stop),
    do:
      entities(state, "route_rules")
      |> Map.values()
      |> Enum.filter(&(&1["stop_id"] == stop))
      |> Enum.map(&RouteTarget.from_row/1)
      |> Enum.sort_by(& &1.id)

  defp single_visit?(state, ship),
    do:
      Enum.any?(entities(state, "visit_plans"), fn {_, p} -> p["ship_id"] == ship end) or
        Enum.any?(entities(state, "ship_instructions"), fn {_, o} ->
          o["ship_id"] == ship and o["status"] in @open
        end)

  def executable?(state, ship) do
    case get(state, "ship_routes", ship) do
      nil -> true
      route -> route.status == "running"
    end
  end

  def advance(state, catalogue) do
    state = expire_waits(state, catalogue)

    entities(state, "ship_routes")
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce(state, fn {id, _}, acc ->
      prepare(acc, get(acc, "ship_routes", id), catalogue)
    end)
  end

  # Capture the arrival before berth retries or handling can replace its timestamp.
  # The stop's configured limit is a template; this deadline belongs to this visit.
  def arrived(state, ship_id, arrived_ms) do
    route = get(state, "ship_routes", ship_id)
    ship = get(state, "ships", ship_id)
    stop = if route, do: Enum.at(stops(state, ship_id), route.cursor)

    if route && route.status != "draft" && is_nil(route.visit_arrived_ms) && stop && ship &&
         ship["status"] != "sailing" && ship["port"] == stop.port do
      put(state, "ship_routes", route.id, %{
        route
        | visit_arrived_ms: arrived_ms,
          wait_deadline_ms: if(stop.max_wait_ms, do: arrived_ms + stop.max_wait_ms)
      })
    else
      state
    end
  end

  def expire_waits(state, catalogue) do
    entities(state, "ship_routes")
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce(state, fn {id, _}, acc ->
      acc = arrived(acc, id, acc.clock_ms)
      route = get(acc, "ship_routes", id)

      if route.status != "draft" and not route.wait_timed_out and
           not is_nil(route.wait_deadline_ms) and acc.clock_ms >= route.wait_deadline_ms and
           (route.phase != "buying" or pending?(acc, id)) do
        expire_visit(acc, route, catalogue)
      else
        acc
      end
    end)
  end

  defp expire_visit(state, route, catalogue) do
    ship = get(state, "ships", route.ship_id)
    stops = stops(state, route.ship_id)
    stop = Enum.at(stops, route.cursor)
    next = Enum.at(stops, rem(route.cursor + 1, length(stops)))

    # Record unstarted targets as cancelled shortfalls, without starting their
    # phase or any trade. Materialized orders keep their original terms/progress.
    sides =
      case route.phase do
        "arrival" -> ["sell", "buy"]
        "selling" -> ["buy"]
        "buying" -> []
      end

    state =
      Enum.reduce(sides, state, fn side, acc ->
        materialize(acc, ship, stop, next, side, catalogue, true)
      end)

    open_orders =
      entities(state, "ship_instructions")
      |> Enum.filter(fn {_, o} ->
        o["ship_id"] == route.ship_id and String.starts_with?(o["id"], "route:") and
          o["status"] in @open
      end)
      |> Enum.sort_by(&elem(&1, 0))

    if open_orders == [] do
      state
    else
      finish_expired_visit(state, route, ship, stop, open_orders, catalogue)
    end
  end

  defp finish_expired_visit(state, route, ship, stop, open_orders, catalogue) do
    state =
      Enum.reduce(open_orders, state, fn {id, _}, acc ->
        TijaraTides.Domain.ShipWorld.VisitOrders.cancel_visit_order(
          acc,
          id,
          "Maximum wait elapsed",
          catalogue
        )
      end)

    state
    |> put("ship_routes", route.id, %{
      route
      | phase: "buying",
        wait_timed_out: true,
        reason: "Maximum wait elapsed"
    })
    |> Notices.notice(
      get(state, "companies", route.company_id)["account_id"],
      "route-timeout:" <> route.id,
      {"route.wait_expired",
       %{
         "ship" => ship["name"],
         "ship_id" => ship["id"],
         "port" => stop.port,
         "shortfalls" =>
           entities(state, "ship_instructions")
           |> Map.values()
           |> Enum.filter(
             &(&1["ship_id"] == ship["id"] and &1["reason"] == "Maximum wait elapsed")
           )
           |> Enum.sort_by(& &1["id"])
           |> Enum.map(&Map.take(&1, ~w(good side quantity filled)))
       }}
    )
  end

  defp prepare(state, %RouteHeader{status: "running"} = route, catalogue) do
    ship = get(state, "ships", route.ship_id)
    stops = stops(state, route.ship_id)
    stop = Enum.at(stops, route.cursor)

    if ship && stop && ship["status"] == "docked" && ship["port"] == stop.port do
      next = Enum.at(stops, rem(route.cursor + 1, length(stops)))

      case route.phase do
        "arrival" ->
          state = materialize(state, ship, stop, next, "sell", catalogue)

          state =
            put(state, "ship_routes", route.id, %{
              route
              | phase: "selling",
                reason: "Completing sale targets"
            })

          prepare(state, get(state, "ship_routes", route.id), catalogue)

        "selling" ->
          if pending?(state, ship["id"]) do
            state
          else
            state = materialize(state, ship, stop, next, "buy", catalogue)

            state =
              put(state, "ship_routes", route.id, %{
                route
                | phase: "buying",
                  reason: "Completing loading targets"
              })

            prepare(state, get(state, "ship_routes", route.id), catalogue)
          end

        "buying" ->
          if route.stop_after and not pending?(state, ship["id"]) do
            pause(state, %{route | stop_after: false}, "Stopped after completing this visit")
          else
            plan =
              VisitPlan.from_row(%{
                "id" => ship["id"] <> "|" <> stop.port,
                "ship_id" => ship["id"],
                "company_id" => ship["company_id"],
                "port" => stop.port,
                "onward" => next.port,
                "auto_depart" => route.auto_depart and not route.stop_after,
                "departure_wait" => nil
              })

            previous = get(state, "visit_plans", plan.id)

            plan =
              if previous,
                do: %{plan | departure_wait: previous.departure_wait},
                else: plan

            put(state, "visit_plans", plan.id, plan)
          end
      end
    else
      state
    end
  end

  defp prepare(state, _, _catalogue), do: state

  defp pending?(state, ship),
    do:
      Enum.any?(entities(state, "ship_instructions"), fn {_, o} ->
        o["ship_id"] == ship and o["status"] in @open
      end)

  defp materialize(state, ship, stop, next, side, catalogue, only_missing \\ false) do
    rules(state, stop.id)
    |> Enum.filter(&(&1.side == side))
    |> Enum.reject(fn rule ->
      only_missing and not is_nil(get(state, "ship_instructions", "route:" <> rule.id))
    end)
    |> Enum.reduce(state, fn rule, acc ->
      aboard =
        Enum.sum(
          for b <- ship["cargo"],
              b["good"] == rule.good,
              side != "buy" or
                CargoRules.qualifies?(b["expires_ms"], state.clock_ms, rule.min_remaining_ms),
              do: b["quantity"]
        )

      item = catalogue["goods"][rule.good]
      class = TijaraTides.Domain.ShipClass.all()[ship["class"]]

      space =
        ship
        |> TijaraTides.Domain.Ship.Rows.decode()
        |> TijaraTides.Domain.Ship.capacity(catalogue)

      free_capacity =
        min(
          div(class["weight"] - space.weight, item["weight_kg"]),
          div(class["volume"] - space.volume, item["volume_l"])
        )

      quantity =
        rule
        |> TijaraTides.Domain.Ship.QuantityPolicy.from_target()
        |> TijaraTides.Domain.Ship.QuantityPolicy.resolve(side, aboard, free_capacity)

      if quantity == 0 do
        acc
      else
        id = "route:" <> rule.id

        order = %{
          "id" => id,
          "ship_id" => ship["id"],
          "company_id" => ship["company_id"],
          "port" => stop.port,
          "good" => rule.good,
          "side" => side,
          "quantity_mode" => rule.quantity_mode || "fixed",
          "quantity" => quantity,
          "filled" => 0,
          "limit" => rule.limit,
          "budget" => rule.budget,
          "min_remaining_ms" => rule.min_remaining_ms,
          "spent" => 0,
          "onward" => if(side == "buy", do: next.port),
          "status" => "planned",
          "reason" => "Route visit target",
          "history_archived" => false,
          "created_ms" => state.clock_ms
        }

        snapshot = TijaraTides.Domain.Ship.VisitOrder.from_row(order)
        put(acc, "ship_instructions", id, TijaraTides.Domain.Ship.VisitOrder.to_row(snapshot))
      end
    end)
  end

  # Fleet calls this only after a successful departure, inside the same transaction.
  def departed(state, ship_id, destination) do
    case get(state, "ship_routes", ship_id) do
      nil ->
        state

      %RouteHeader{status: "draft"} ->
        state

      route ->
        stops = stops(state, ship_id)
        current = Enum.at(stops, route.cursor)
        budget = State.get(state, "visit_budgets", current.id)

        # Successful departure ends this visit even when its targets are unfinished
        # or the route is paused. Keep the separately reserved inbound visit intact.
        state =
          if budget && budget["ship_id"] == ship_id && budget["visit"] == route.visit,
            do: TijaraTides.Domain.AutomationWorld.release_visit(state, budget),
            else: state

        index = rem(route.cursor + 1, length(stops))

        if Enum.at(stops, index).port == destination do
          state
          |> clear_visit(ship_id)
          |> put("ship_routes", ship_id, %{
            route
            | cursor: index,
              visit: route.visit + 1,
              phase: "arrival",
              visit_finished: false,
              visit_arrived_ms: nil,
              wait_deadline_ms: nil,
              wait_timed_out: false,
              reason: if(route.wait_timed_out, do: "Following route", else: route.reason)
          })
        else
          pause(
            state,
            %{
              route
              | phase: "arrival",
                visit_finished: false,
                visit_arrived_ms: nil,
                wait_deadline_ms: nil,
                wait_timed_out: false
            },
            "Off route; return to the selected stop before resuming"
          )
          |> clear_visit(ship_id)
        end
    end
  end

  defp clear_visit(state, ship) do
    Enum.reduce(["ship_instructions", "visit_plans"], state, fn kind, acc ->
      Enum.reduce(entities(acc, kind), acc, fn {id, row}, acc ->
        if row["ship_id"] == ship and (kind == "visit_plans" or String.starts_with?(id, "route:")),
          do: delete(acc, kind, id),
          else: acc
      end)
    end)
  end

  def divert(state, ship_id) do
    case get(state, "ship_routes", ship_id) do
      %RouteHeader{status: "running"} = route ->
        pause(state, route, "Paused by player; committed handling continues")

      _ ->
        state
    end
  end

  defp pause(state, route, reason) do
    state =
      put(state, "ship_routes", route.id, %{route | status: "paused", reason: reason})

    company = get(state, "companies", route.company_id)

    Notices.notice(
      state,
      company["account_id"],
      "route:" <> route.id,
      {"route.paused", %{"reason" => reason}}
    )
  end
end
