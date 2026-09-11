defmodule TijaraTides.Domain.Ship.VisitOrders do
  @moduledoc "Private, single-visit cargo instructions; fills and progress settle in the same world transaction."
  import TijaraTides.Domain.State
  alias TijaraTides.Domain.{CargoRules, Notices}

  @open ["planned", "waiting"]

  def add(state, account, params, context) do
    ship = get(state, "ships", params["ship"])
    catalogue = context.catalogue
    good = catalogue["goods"][params["good"]]
    port = params["port"]
    side = params["side"]
    quantity = params["quantity"]
    limit = params["limit"]
    budget = params["budget"]
    onward = params["onward"]

    cond do
      is_nil(ship) or is_nil(account["company_id"]) or ship["company_id"] != account["company_id"] ->
        {:error, :instruction_ship_not_owned}

      # Whether a ship runs a route is private, so never answer before ownership.
      get(state, "ship_routes", params["ship"]) != nil ->
        {:error, :route_owns_instructions}

      ship["status"] not in ["docked", "loading", "unloading", "sailing"] or
        is_nil(catalogue["ports"][port]) or port == ship["port"] or
          (ship["status"] == "sailing" and port != ship["destination"]) ->
        {:error, :instruction_destination_invalid}

      side not in ["buy", "sell"] or is_nil(good) or good["manual"] != true or
        not CargoRules.compatible_cargo?(ship, good) or
          is_nil(get(state, "markets", port <> "|" <> params["good"])) ->
        {:error, :instruction_cargo_invalid}

      not is_integer(quantity) or quantity < 1 or quantity > 10_000 or
        not is_integer(limit) or limit < 0 or limit > 1_000_000_000_000 ->
        {:error, :instruction_quantity_invalid}

      side == "sell" and
          quantity >
            Enum.sum(
              for batch <- ship["cargo"], batch["good"] == params["good"], do: batch["quantity"]
            ) ->
        {:error, :instruction_sell_exceeds_cargo}

      side == "sell" and
          Enum.any?(entities(state, "ship_instructions"), fn {_, order} ->
            order["ship_id"] == ship["id"] and order["good"] == params["good"] and
              order["side"] == "sell" and order["status"] in @open
          end) ->
        {:error, :instruction_duplicate_sell}

      side == "buy" and visit_onwards(state, ship["id"], port) not in [[], [onward]] ->
        {:error, :instruction_onward_conflict}

      side == "buy" and
          (not is_integer(budget) or budget < 1 or budget > 1_000_000_000_000 or
             is_nil(catalogue["ports"][onward]) or onward == port) ->
        {:error, :instruction_budget_invalid}

      Enum.count(entities(state, "ship_instructions"), fn {_, order} ->
        order["ship_id"] == ship["id"] and order["status"] in @open
      end) >= 20 ->
        {:error, :instruction_limit_reached}

      true ->
        order = %{
          "id" => context.id,
          "company_id" => ship["company_id"],
          "ship_id" => ship["id"],
          "port" => port,
          "good" => params["good"],
          "side" => side,
          "quantity_mode" => "fixed",
          "quantity" => quantity,
          "filled" => 0,
          "limit" => limit,
          "budget" => if(side == "buy", do: budget),
          "spent" => 0,
          "onward" => if(side == "buy", do: onward),
          "status" => "planned",
          "reason" => "Awaiting arrival and a berth",
          "created_ms" => state.clock_ms
        }

        state = if side == "buy", do: save_visit(state, ship, port, onward), else: state

        {:ok, put(state, "ship_instructions", order["id"], order),
         %{"instruction_id" => order["id"]}}
    end
  end

  def change_onward(state, account, ship_id, port, onward, catalogue, auto_depart \\ nil) do
    ship = get(state, "ships", ship_id)
    orders = visit_buys(state, ship_id, port)

    cond do
      is_nil(ship) or is_nil(account["company_id"]) or ship["company_id"] != account["company_id"] ->
        {:error, :instruction_ship_not_owned}

      # Whether a ship runs a route is private, so never answer before ownership.
      get(state, "ship_routes", ship_id) != nil ->
        {:error, :route_owns_instructions}

      is_nil(catalogue["ports"][port]) or
          (ship["status"] == "sailing" and port != ship["destination"]) ->
        {:error, :instruction_destination_invalid}

      auto_depart not in [nil, true, false] ->
        {:error, :instruction_auto_depart_invalid}

      is_nil(catalogue["ports"][onward]) or onward == port ->
        {:error, :instruction_onward_invalid}

      true ->
        changed =
          Enum.reduce(orders, state, fn order, state ->
            put(state, "ship_instructions", order["id"], %{order | "onward" => onward})
          end)

        changed = save_visit(changed, ship, port, onward, auto_depart)
        {:ok, changed, %{"onward" => onward}}
    end
  end

  defp visit_buys(state, ship_id, port) do
    entities(state, "ship_instructions")
    |> Map.values()
    |> Enum.filter(
      &(&1["ship_id"] == ship_id and &1["port"] == port and &1["side"] == "buy" and
          &1["status"] in @open)
    )
  end

  defp save_visit(state, ship, port, onward, auto_depart \\ nil) do
    id = ship["id"] <> "|" <> port
    previous = get(state, "visit_plans", id)

    enabled =
      if is_nil(auto_depart),
        do: previous != nil && previous["auto_depart"] == true,
        else: auto_depart

    put(state, "visit_plans", id, %{
      "id" => id,
      "ship_id" => ship["id"],
      "company_id" => ship["company_id"],
      "port" => port,
      "onward" => onward,
      "auto_depart" => enabled,
      "departure_wait" => nil
    })
  end

  def visit_onwards(state, ship_id, port) do
    plan = get(state, "visit_plans", ship_id <> "|" <> port)

    visit_buys(state, ship_id, port)
    |> Enum.map(& &1["onward"])
    |> Kernel.++(if(plan, do: [plan["onward"]], else: []))
    |> Enum.uniq()
  end

  def cancel(state, account, id, catalogue) do
    company_id = account["company_id"]

    case get(state, "ship_instructions", id) do
      %{"company_id" => owner, "status" => status} = order
      when owner != nil and owner == company_id and status in @open ->
        {:ok, finish(state, order, "Cancelled by player", catalogue), %{"instruction_id" => id}}

      _ ->
        {:error, :instruction_not_active}
    end
  end

  # Called only after departure succeeds. Never carry a waiting remainder into
  # another visit, or keep a plan for a destination the ship sailed away from.
  def depart(state, ship_id, destination, catalogue) do
    state =
      Enum.reduce(entities(state, "visit_plans"), state, fn {id, plan}, state ->
        if plan["ship_id"] == ship_id and plan["port"] != destination,
          do: delete(state, "visit_plans", id),
          else: state
      end)

    state =
      Enum.reduce(entities(state, "ship_instructions"), state, fn {_, order}, state ->
        if order["ship_id"] == ship_id and order["status"] in @open and
             (order["status"] == "waiting" or order["port"] != destination),
           do: finish(state, order, "Cancelled remainder on departure", catalogue),
           else: state
      end)

    TijaraTides.Domain.Ship.RoutePlan.departed(state, ship_id, destination)
  end

  def wait_for_departure(state, id, reason),
    do: departure_wait(state, get(state, "visit_plans", id), reason)

  def wait_for_order(state, id, reason, catalogue),
    do: wait(state, get(state, "ship_instructions", id), reason, catalogue)

  def cancel_visit_order(state, id, reason, catalogue),
    do: finish(state, get(state, "ship_instructions", id), reason, catalogue)

  def complete_visit_order(state, id, reason, catalogue) do
    order = get(state, "ship_instructions", id)

    unless order["quantity_mode"] == "maximum" and order["status"] in @open,
      do: raise(ArgumentError, "Only an open maximum instruction can complete below its target")

    update(state, %{order | "status" => "filled", "reason" => reason}, catalogue)
  end

  def record_visit_fill(state, id, quantity, spent, catalogue) do
    order =
      get(state, "ship_instructions", id)
      |> TijaraTides.Domain.Ship.VisitOrder.from_row()
      |> TijaraTides.Domain.Ship.VisitOrder.record_fill(quantity, spent)
      |> TijaraTides.Domain.Ship.VisitOrder.to_row()

    update(state, order, catalogue)
  end

  defp departure_wait(state, plan, reason) do
    if plan["departure_wait"] == reason do
      state
    else
      ship = get(state, "ships", plan["ship_id"])
      company = get(state, "companies", ship["company_id"])

      state
      |> put("visit_plans", plan["id"], Map.put(plan, "departure_wait", reason))
      |> Notices.notice(
        company["account_id"],
        "auto-depart:" <> plan["id"],
        "#{ship["name"]}: automatic departure to #{plan["onward"]} paused. #{reason}."
      )
    end
  end

  defp wait(state, order, reason, catalogue),
    do: update(state, %{order | "status" => "waiting", "reason" => reason}, catalogue)

  defp finish(state, order, reason, catalogue),
    do: update(state, %{order | "status" => "cancelled", "reason" => reason}, catalogue)

  defp update(state, order, catalogue) do
    previous = get(state, "ship_instructions", order["id"])

    if previous == order do
      state
    else
      company = get(state, "companies", order["company_id"])
      ship = get(state, "ships", order["ship_id"])

      state
      |> put("ship_instructions", order["id"], order)
      |> Notices.notice(
        company["account_id"],
        "instruction:" <> order["id"],
        "#{ship["name"]} at #{order["port"]}: #{order["side"]} #{catalogue["goods"][order["good"]]["name"]}, #{order["filled"]}/#{order["quantity"]} lots filled. #{order["reason"]}."
      )
    end
  end
end
