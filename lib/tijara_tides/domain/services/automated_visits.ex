defmodule TijaraTides.Domain.Services.AutomatedVisits do
  alias TijaraTides.Domain.WarehouseWorld
  alias TijaraTides.Domain.ShipWorld

  @moduledoc "Coordinate visit fills and automatic departures across ship, market and finance roots."
  import TijaraTides.Domain.State, only: [get: 3, entities: 2]
  alias TijaraTides.Domain.{Fleet, Trade}
  alias TijaraTides.Domain.Services.TradeSettlement, as: Trading
  @open ["planned", "waiting"]
  def advance(before, catalogue) do
    state = TijaraTides.Domain.Services.DepartureFunding.prepare_visits(before, catalogue)
    # Stable order across restarts; sell instructions always precede purchases.
    entities(state, "ship_instructions")
    |> Map.values()
    |> Enum.filter(
      &(&1["status"] in @open and
          ShipWorld.automation_enabled?(state, &1["ship_id"]))
    )
    |> Enum.sort_by(&{if(&1["side"] == "sell", do: 0, else: 1), &1["created_ms"], &1["id"]})
    |> Enum.reduce(state, &attempt(&2, &1, catalogue))
    |> TijaraTides.Domain.Services.DepartureFunding.advance(catalogue)
    |> then(&TijaraTides.Domain.OrderBookWorld.synchronize_changed(before, &1))
  end

  defp attempt(state, order, catalogue) do
    ship = get(state, "ships", order["ship_id"])
    visit_budget = ship && TijaraTides.Domain.AutomationWorld.budget(state, ship, order["port"])

    if order["status"] in @open && ship && is_nil(ship["pending_side"]) &&
         ship["status"] == "docked" &&
         ship["port"] == order["port"] do
      company = get(state, "companies", order["company_id"])
      account = get(state, "accounts", company["account_id"])
      remaining = order["quantity"] - order["filled"]

      maximum_buy =
        order["quantity_mode"] == "maximum" and order["side"] == "buy"

      maximum_sell =
        order["quantity_mode"] == "maximum" and order["side"] == "sell"

      trade = %Trade{
        side: order["side"],
        ship_id: ship["id"],
        good: order["good"],
        quantity: 1,
        limit: order["limit"],
        markdowns: order["markdowns"],
        price_floor: order["price_floor"] || 0,
        purchase_budget_id: if(visit_budget && visit_budget["strict"], do: visit_budget["id"]),
        min_remaining_ms: Map.get(order, "min_remaining_ms", 0),
        destination: order["onward"]
      }

      source =
        if order["side"] == "buy",
          do:
            WarehouseWorld.collection_source(
              state,
              ship,
              order["good"],
              trade.min_remaining_ms,
              catalogue
            )

      # Pure probes are discarded. Only the final successful fill is committed.
      result = fn quantity ->
        case execute_fill(state, account, %{trade | quantity: quantity}, source, catalogue) do
          {:ok, changed, reply} ->
            if order["side"] == "buy" and not is_nil(order["budget"]) and
                 order["spent"] + (reply["spent"] || 0) > order["budget"],
               do: {:error, :instruction_budget_exhausted},
               else: {:ok, changed, reply}

          error ->
            error
        end
      end

      first =
        if visit_budget && visit_budget["skip"] && order["side"] == "buy" && is_nil(source),
          do: {:error, :purchases_skipped},
          else:
            if(
              length(ShipWorld.visit_onwards(state, ship["id"], order["port"])) > 1 and
                order["side"] == "buy",
              do: {:error, :instruction_onward_conflict},
              else: result.(1)
            )

      case first do
        {:error, :purchases_skipped} ->
          finish(state, order, "Purchases skipped for this visit", catalogue)

        {:error, :berth_busy} ->
          state
          |> TijaraTides.Domain.Services.BerthAllocation.enqueue(ship["id"])
          |> wait(order, "Waiting for a berth", catalogue)

        {:error, :capacity_exceeded} ->
          sales_pending =
            Enum.any?(entities(state, "ship_instructions"), fn {_, other} ->
              other["ship_id"] == order["ship_id"] and other["port"] == order["port"] and
                other["side"] == "sell" and other["status"] in @open
            end)

          plan = get(state, "visit_plans", ship["id"] <> "|" <> order["port"])

          route = get(state, "ship_routes", ship["id"])

          if sales_pending or ((is_nil(route) and plan) && plan["auto_depart"] == true),
            do:
              wait(
                state,
                order,
                "Waiting for hold capacity; fill or cancel remaining orders",
                catalogue
              ),
            else:
              finish(
                state,
                order,
                "Hold capacity exhausted; cancelled unfilled remainder",
                catalogue
              )

        {:error, reason} ->
          if (maximum_sell and reason in [:insufficient_demand, :insufficient_cargo]) or
               (maximum_buy and
                  (reason in [
                     :insufficient_supply,
                     :insufficient_cash,
                     :instruction_budget_exhausted
                   ] or match?({:purchase_voyage_funds, _, _, _}, reason))),
             do:
               ShipWorld.complete_visit_order(
                 state,
                 order["id"],
                 if(maximum_sell,
                   do: "Available demand exhausted; unsold cargo stays aboard",
                   else: "Maximum available purchase completed"
                 ),
                 catalogue
               ),
             else: wait(state, order, reason_text(reason), catalogue)

        {:ok, _, _} ->
          quantity = maximum(1, min(remaining, 10_000), result)
          {:ok, changed, reply} = result.(quantity)

          ShipWorld.record_visit_fill(
            changed,
            order["id"],
            quantity,
            reply["spent"] || 0,
            catalogue
          )
      end
    else
      if ship && ship["port"] == order["port"] && ship["status"] in ["loading", "unloading"],
        do: wait(state, order, "Waiting for handling to finish", catalogue),
        else: state
    end
  end

  defp execute_fill(state, account, trade, source, catalogue, admission \\ :normal)

  defp execute_fill(state, account, trade, nil, catalogue, :validate),
    do:
      Trading.check(
        TijaraTides.Domain.Services.LinkedOrders.handover(state, trade.ship_id),
        account,
        trade,
        catalogue
      )

  defp execute_fill(state, account, trade, nil, catalogue, :normal),
    do:
      Trading.execute(
        TijaraTides.Domain.Services.LinkedOrders.handover(state, trade.ship_id),
        account,
        trade,
        catalogue
      )

  defp execute_fill(state, account, trade, warehouse, catalogue, admission) do
    state = TijaraTides.Domain.Services.LinkedOrders.handover(state, trade.ship_id)

    case TijaraTides.Domain.Services.ShipLifecycle.transfer_warehouse(
           state,
           account,
           %{
             "warehouse" => warehouse.id,
             "ship" => trade.ship_id,
             "good" => trade.good,
             "quantity" => trade.quantity,
             "min_remaining_ms" => trade.min_remaining_ms,
             "side" => "collect"
           },
           catalogue,
           admission
         ) do
      {:ok, changed, reply} ->
        ship = get(changed, "ships", trade.ship_id)

        quote =
          Fleet.voyage_quote(
            %{ship | "status" => "docked"},
            trade.destination,
            catalogue,
            changed.clock_ms + max(0, ship["arrive_ms"] - changed.clock_ms),
            changed.clock_ms
          )

        company = get(changed, "companies", ship["company_id"])

        if quote && company["cash"] - company["reserved"] >= quote["fuel"] + quote["canal_fees"],
          do: {:ok, changed, reply},
          else: {:error, :insufficient_cash}

      {:error, :warehouse_berth_busy} ->
        {:error, :berth_busy}

      other ->
        other
    end
  end

  @doc "Probe the same qualifying owned-stock or market source used by visit execution."
  def validate(state, account, trade, catalogue) do
    ship = get(state, "ships", trade.ship_id)

    budget = TijaraTides.Domain.AutomationWorld.budget(state, ship, ship["port"])
    trade = %{trade | purchase_budget_id: if(budget && budget["strict"], do: budget["id"])}

    source =
      if trade.side == "buy",
        do:
          WarehouseWorld.collection_source(
            state,
            ship,
            trade.good,
            trade.min_remaining_ms,
            catalogue
          )

    case execute_fill(
           Map.put(state, :lot_allocation, {:local, 1}),
           account,
           trade,
           source,
           catalogue,
           :validate
         ) do
      {:ok, _, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maximum(low, high, _result) when low == high, do: low

  defp maximum(low, high, result) do
    mid = div(low + high + 1, 2)

    case result.(mid) do
      {:ok, _, _} -> maximum(mid, high, result)
      {:error, _} -> maximum(low, mid - 1, result)
    end
  end

  defp wait(state, order, reason, catalogue),
    do: ShipWorld.wait_for_order(state, order["id"], reason, catalogue)

  defp finish(state, order, reason, catalogue),
    do: ShipWorld.cancel_visit_order(state, order["id"], reason, catalogue)

  defp reason_text(:instruction_onward_conflict),
    do: "Choose one shared onward port for this visit before purchases can resume"

  defp reason_text(:price_changed), do: "Waiting for the limit price"
  defp reason_text(:insufficient_cargo), do: "Waiting for cargo aboard"
  defp reason_text(:insufficient_supply), do: "Waiting for market supply"

  defp reason_text(:insufficient_fresh_cargo),
    do: "Waiting for cargo meeting the minimum remaining shelf life"

  defp reason_text(:insufficient_demand), do: "Waiting for market demand or buyer funds"

  defp reason_text(:insufficient_cash),
    do: "Waiting for available company funds or unpaid costs to clear"

  defp reason_text(:instruction_budget_exhausted), do: "Purchase spending cap exhausted"

  defp reason_text({:purchase_voyage_funds, _, _, _}),
    do: "Waiting for funds after preserving onward voyage costs"

  defp reason_text(:purchase_destination_required), do: "Onward voyage is unavailable"
  defp reason_text(_), do: "Cargo is currently unavailable for trading at this port"
end
