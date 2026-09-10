defmodule TijaraTides.Domain.ShipRoutes do
  @moduledoc "Private repeating stop templates and their current visit. Execution uses ordinary ship instructions."
  import TijaraTides.Domain.State
  alias TijaraTides.Domain.{CargoRules, Notices}
  @open ["planned", "waiting"]

  def execute(state, account, params, context) do
    ship = get(state, "ships", params["ship"])
    company = get(state, "companies", account["company_id"])

    if is_nil(ship) or is_nil(company) or ship["company_id"] != company["id"] or
         company["bankruptcy_ms"] != nil do
      {:error, :route_ship_not_owned}
    else
      case edit(state, ship, params, context) do
        {:ok, changed, _} = result ->
          route = get(changed, "ship_routes", ship["id"])
          stops = stops(changed, ship["id"])

          if route && route["status"] != "draft" &&
               (length(stops) < 2 or
                  Enum.any?(Enum.zip(stops, tl(stops) ++ [hd(stops)]), fn {a, b} ->
                    is_nil(context.catalogue["routes"][a["port"] <> "|" <> b["port"]])
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
      route && route["status"] != "draft" && route["phase"] != "arrival" &&
          route["cursor"] == length(stops) - 1 ->
        {:error, :route_stop_committed}

      is_nil(route) and single_visit?(state, ship["id"]) ->
        {:error, :route_existing_instructions}

      length(stops) >= 8 ->
        {:error, :route_stop_limit}

      is_nil(context.catalogue["ports"][port]) or
          (stops != [] and List.last(stops)["port"] == port) ->
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

        stop = %{
          "id" => context.id,
          "ship_id" => ship["id"],
          "company_id" => ship["company_id"],
          "position" => length(stops),
          "port" => port
        }

        {:ok,
         state |> put("ship_routes", ship["id"], route) |> put("route_stops", stop["id"], stop),
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
        &(&1["id"] == p["rule"] and operation == "update_rule")
      )

    cond do
      is_nil(route) or
          (operation == "update_rule" and
             (is_nil(existing) or existing["ship_id"] != ship["id"] or
                existing["stop_id"] != p["stop"])) ->
        {:error, :route_edit_draft}

      is_nil(stop) or stop["ship_id"] != ship["id"] ->
        {:error, :route_port_invalid}

      is_nil(good) or good["manual"] != true or not CargoRules.compatible_class?(ship, good) or
          is_nil(get(state, "markets", stop["port"] <> "|" <> p["good"])) ->
        {:error, :instruction_cargo_invalid}

      p["side"] not in ["buy", "sell"] or
        Map.get(p, "quantity_mode", "fixed") not in ["fixed", "maximum"] or
        (Map.get(p, "quantity_mode", "fixed") == "fixed" and
           (not is_integer(p["quantity"]) or p["quantity"] not in 1..10_000)) or
        not is_integer(p["limit"]) or
          p["limit"] not in 0..1_000_000_000_000 ->
        {:error, :instruction_quantity_invalid}

      p["side"] == "buy" and not is_nil(p["budget"]) and
          (not is_integer(p["budget"]) or p["budget"] not in 1..1_000_000_000_000) ->
        {:error, :instruction_budget_invalid}

      length(rules) >= 20 or
          Enum.any?(rules, &(&1["side"] == p["side"] and &1["good"] == p["good"])) ->
        {:error, :route_duplicate_rule}

      true ->
        rule =
          Map.take(p, ~w(side good quantity limit))
          |> Map.merge(%{
            "quantity_mode" => Map.get(p, "quantity_mode", "fixed"),
            "quantity" => if(p["quantity_mode"] == "maximum", do: nil, else: p["quantity"]),
            "id" => if(existing, do: existing["id"], else: context.id),
            "ship_id" => ship["id"],
            "company_id" => ship["company_id"],
            "stop_id" => stop["id"],
            "budget" => if(p["side"] == "buy", do: p["budget"])
          })

        {:ok, put(state, "route_rules", rule["id"], rule), %{}}
    end
  end

  defp edit(state, ship, %{"operation" => "remove_rule", "rule" => id}, _context) do
    route = get(state, "ship_routes", ship["id"])
    rule = get(state, "route_rules", id)

    if route && rule && rule["ship_id"] == ship["id"],
      do: {:ok, delete(state, "route_rules", id), %{}},
      else: {:error, :route_edit_draft}
  end

  defp edit(state, ship, %{"operation" => "remove_stop", "stop" => id}, _context) do
    route = get(state, "ship_routes", ship["id"])
    stop = get(state, "route_stops", id)

    all = stops(state, ship["id"])
    current = if route, do: Enum.at(all, route["cursor"])

    protected =
      if route && route["status"] != "draft",
        do: [route["cursor"], rem(route["cursor"] + 1, length(all))],
        else: []

    if route && stop && stop["ship_id"] == ship["id"] && stop["position"] not in protected do
      state =
        Enum.reduce(rules(state, id), state, &delete(&2, "route_rules", &1["id"]))
        |> delete("route_stops", id)

      state =
        stops(state, ship["id"])
        |> Enum.with_index()
        |> Enum.reduce(state, fn {s, n}, acc ->
          put(acc, "route_stops", s["id"], %{s | "position" => n})
        end)

      state =
        if current && route["status"] != "draft",
          do:
            put(state, "ship_routes", route["id"], %{
              route
              | "cursor" => get(state, "route_stops", current["id"])["position"]
            }),
          else: state

      {:ok, state, %{}}
    else
      {:error, :route_stop_committed}
    end
  end

  defp edit(state, ship, %{"operation" => operation} = p, context) do
    route = get(state, "ship_routes", ship["id"])
    stops = stops(state, ship["id"])
    current = Enum.at(stops, if(route, do: route["cursor"], else: 0))

    cond do
      is_nil(route) ->
        {:error, :route_missing}

      operation in ["start", "resume"] ->
        cond do
          length(stops) < 2 or hd(stops)["port"] == List.last(stops)["port"] ->
            {:error, :route_needs_stops}

          Map.get(p, "auto_depart", true) not in [true, false] ->
            {:error, :instruction_auto_depart_invalid}

          is_nil(current) or
              if(ship["status"] == "sailing", do: ship["destination"], else: ship["port"]) !=
                current["port"] ->
            {:error, :route_start_port}

          Enum.any?(Enum.zip(stops, tl(stops) ++ [hd(stops)]), fn {a, b} ->
            is_nil(context.catalogue["routes"][a["port"] <> "|" <> b["port"]])
          end) ->
            {:error, :route_port_invalid}

          true ->
            {:ok,
             put(state, "ship_routes", ship["id"], %{
               route
               | "status" => "running",
                 "auto_depart" => Map.get(p, "auto_depart", true),
                 "stop_after" => false,
                 "reason" => "Following route"
             }), %{}}
        end

      operation == "pause" ->
        {:ok, pause(state, route, "Paused by player; committed handling continues"), %{}}

      operation == "stop_after" and route["status"] == "running" ->
        {:ok, put(state, "ship_routes", ship["id"], %{route | "stop_after" => true}), %{}}

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
      |> Enum.sort_by(& &1["position"])

  defp rules(state, stop),
    do:
      entities(state, "route_rules")
      |> Map.values()
      |> Enum.filter(&(&1["stop_id"] == stop))
      |> Enum.sort_by(& &1["id"])

  defp single_visit?(state, ship),
    do:
      Enum.any?(entities(state, "visit_plans"), fn {_, p} -> p["ship_id"] == ship end) or
        Enum.any?(entities(state, "ship_instructions"), fn {_, o} ->
          o["ship_id"] == ship and o["status"] in @open
        end)

  def executable?(state, ship) do
    case get(state, "ship_routes", ship) do
      nil -> true
      route -> route["status"] == "running"
    end
  end

  def advance(state, catalogue) do
    entities(state, "ship_routes")
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce(state, fn {id, _}, acc ->
      prepare(acc, get(acc, "ship_routes", id), catalogue)
    end)
  end

  defp prepare(state, %{"status" => "running"} = route, catalogue) do
    ship = get(state, "ships", route["ship_id"])
    stops = stops(state, route["ship_id"])
    stop = Enum.at(stops, route["cursor"])

    if ship && stop && ship["status"] == "docked" && ship["port"] == stop["port"] do
      next = Enum.at(stops, rem(route["cursor"] + 1, length(stops)))

      case route["phase"] do
        "arrival" ->
          state = materialize(state, ship, stop, next, "sell", catalogue)

          state =
            put(state, "ship_routes", route["id"], %{
              route
              | "phase" => "selling",
                "reason" => "Completing sale targets"
            })

          prepare(state, get(state, "ship_routes", route["id"]), catalogue)

        "selling" ->
          if pending?(state, ship["id"]) do
            state
          else
            state = materialize(state, ship, stop, next, "buy", catalogue)

            state =
              put(state, "ship_routes", route["id"], %{
                route
                | "phase" => "buying",
                  "reason" => "Completing loading targets"
              })

            prepare(state, get(state, "ship_routes", route["id"]), catalogue)
          end

        "buying" ->
          if route["stop_after"] and not pending?(state, ship["id"]) do
            pause(state, %{route | "stop_after" => false}, "Stopped after completing this visit")
          else
            plan = %{
              "id" => ship["id"] <> "|" <> stop["port"],
              "ship_id" => ship["id"],
              "company_id" => ship["company_id"],
              "port" => stop["port"],
              "onward" => next["port"],
              "auto_depart" => route["auto_depart"] and not route["stop_after"],
              "departure_wait" => nil
            }

            previous = get(state, "visit_plans", plan["id"])

            plan =
              if previous,
                do: Map.put(plan, "departure_wait", previous["departure_wait"]),
                else: plan

            put(state, "visit_plans", plan["id"], plan)
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

  defp materialize(state, ship, stop, next, side, catalogue) do
    rules(state, stop["id"])
    |> Enum.filter(&(&1["side"] == side))
    |> Enum.reduce(state, fn rule, acc ->
      aboard = Enum.sum(for b <- ship["cargo"], b["good"] == rule["good"], do: b["quantity"])

      quantity =
        cond do
          rule["quantity_mode"] == "maximum" and side == "buy" ->
            item = catalogue["goods"][rule["good"]]
            class = TijaraTides.Domain.Fleet.classes()[ship["class"]]
            space = TijaraTides.Domain.Fleet.capacity(ship, catalogue)

            min(
              div(class["weight"] - space.weight, item["weight_kg"]),
              div(class["volume"] - space.volume, item["volume_l"])
            )

          rule["quantity_mode"] == "maximum" ->
            aboard

          side == "buy" ->
            max(0, rule["quantity"] - aboard)

          true ->
            min(rule["quantity"], aboard)
        end

      if quantity == 0 do
        acc
      else
        id = "route:" <> rule["id"]

        order = %{
          "id" => id,
          "ship_id" => ship["id"],
          "company_id" => ship["company_id"],
          "port" => stop["port"],
          "good" => rule["good"],
          "side" => side,
          "quantity_mode" => rule["quantity_mode"] || "fixed",
          "quantity" => quantity,
          "filled" => 0,
          "limit" => rule["limit"],
          "budget" => rule["budget"],
          "spent" => 0,
          "onward" => if(side == "buy", do: next["port"]),
          "status" => "planned",
          "reason" => "Route visit target",
          "created_ms" => state.clock_ms
        }

        put(acc, "ship_instructions", id, order)
      end
    end)
  end

  # Fleet calls this only after a successful departure, inside the same transaction.
  def departed(state, ship_id, destination) do
    case get(state, "ship_routes", ship_id) do
      nil ->
        state

      %{"status" => "draft"} ->
        state

      route ->
        stops = stops(state, ship_id)
        index = rem(route["cursor"] + 1, length(stops))

        if Enum.at(stops, index)["port"] == destination do
          state
          |> clear_visit(ship_id)
          |> put("ship_routes", ship_id, %{
            route
            | "cursor" => index,
              "visit" => route["visit"] + 1,
              "phase" => "arrival"
          })
        else
          pause(
            state,
            %{route | "phase" => "arrival"},
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

  defp pause(state, route, reason) do
    state =
      put(state, "ship_routes", route["id"], %{route | "status" => "paused", "reason" => reason})

    company = get(state, "companies", route["company_id"])
    Notices.notice(state, company["account_id"], "route:" <> route["id"], reason)
  end
end
