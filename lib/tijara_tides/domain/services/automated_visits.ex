defmodule TijaraTides.Domain.Services.AutomatedVisits do
  @moduledoc "Coordinate visit fills and automatic departures across ship, market and finance roots."
  import TijaraTides.Domain.State, only: [get: 3, entities: 2]
  alias TijaraTides.Domain.{Ship, Fleet, Notices, Trade}
  alias TijaraTides.Domain.Services.TradeSettlement, as: Trading
  @open ["planned", "waiting"]
  def advance(state, catalogue) do
    state = Ship.prepare_visits(state, catalogue)
    # Stable order across restarts; sell instructions always precede purchases.
    entities(state, "ship_instructions")
    |> Map.values()
    |> Enum.filter(
      &(&1["status"] in @open and
          Ship.automation_enabled?(state, &1["ship_id"]))
    )
    |> Enum.sort_by(&{if(&1["side"] == "sell", do: 0, else: 1), &1["created_ms"], &1["id"]})
    |> Enum.reduce(state, &attempt(&2, &1, catalogue))
    |> depart_ready_visits(catalogue)
  end

  defp depart_ready_visits(state, catalogue) do
    entities(state, "visit_plans")
    |> Enum.sort_by(fn {id, _} -> id end)
    |> Enum.reduce(state, fn {id, plan}, state ->
      ship = get(state, "ships", plan["ship_id"])

      if plan["auto_depart"] == true and
           Ship.automation_enabled?(state, plan["ship_id"]) and
           not is_nil(ship) and
           ship["port"] == plan["port"] and
           ship["status"] in ["docked", "loading", "unloading"] do
        pending =
          Enum.any?(entities(state, "ship_instructions"), fn {_, order} ->
            order["ship_id"] == ship["id"] and order["port"] == plan["port"] and
              order["status"] in @open
          end)

        cond do
          ship["status"] != "docked" ->
            departure_wait(state, plan, "Waiting for cargo handling to finish")

          pending ->
            departure_wait(state, plan, "Waiting for cargo orders to be filled or cancelled")

          true ->
            company = get(state, "companies", ship["company_id"])
            account = get(state, "accounts", company["account_id"])
            quote = Fleet.voyage_quote(ship, plan["onward"], catalogue)

            case Fleet.sail(
                   state,
                   account,
                   ship["id"],
                   plan["onward"],
                   if(quote, do: quote["fuel"], else: 0),
                   catalogue
                 ) do
              {:ok, changed, _} ->
                Notices.notice(
                  changed,
                  account["id"],
                  "auto-depart:" <> id,
                  "#{ship["name"]} automatically departed #{plan["port"]} for #{plan["onward"]}."
                )

              {:error, reason} ->
                departure_wait(state, plan, departure_reason(reason))
            end
        end
      else
        state
      end
    end)
  end

  defp departure_reason({:departure_funds, _, _, _}),
    do: "Waiting for available funds for fuel and canal fees"

  defp departure_reason({:departure_unpaid, _}), do: "Waiting for unpaid operating costs to clear"

  defp departure_reason({:departure_no_route, _, _}),
    do: "No sea route is available to the onward destination"

  defp departure_reason({:departure_too_long, _}),
    do: "The onward voyage exceeds the maximum duration"

  defp departure_reason(_), do: "The onward destination is unavailable; update the visit plan"

  defp attempt(state, order, catalogue) do
    ship = get(state, "ships", order["ship_id"])

    if ship && ship["status"] == "docked" && ship["port"] == order["port"] do
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
        destination: order["onward"]
      }

      # Pure probes are discarded. Only the final successful fill is committed.
      result = fn quantity ->
        case Trading.execute(state, account, %{trade | quantity: quantity}, catalogue) do
          {:ok, changed, reply} ->
            if order["side"] == "buy" and not is_nil(order["budget"]) and
                 order["spent"] + reply["spent"] > order["budget"],
               do: {:error, :instruction_budget_exhausted},
               else: {:ok, changed, reply}

          error ->
            error
        end
      end

      first =
        if length(Ship.visit_onwards(state, ship["id"], order["port"])) > 1 and
             order["side"] == "buy",
           do: {:error, :instruction_onward_conflict},
           else: result.(1)

      case first do
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
               Ship.complete_visit_order(
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

          Ship.record_visit_fill(changed, order["id"], quantity, reply["spent"] || 0, catalogue)
      end
    else
      if ship && ship["port"] == order["port"] && ship["status"] in ["loading", "unloading"],
        do: wait(state, order, "Waiting for handling to finish", catalogue),
        else: state
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
    do: Ship.wait_for_order(state, order["id"], reason, catalogue)

  defp finish(state, order, reason, catalogue),
    do: Ship.cancel_visit_order(state, order["id"], reason, catalogue)

  defp departure_wait(state, plan, reason), do: Ship.wait_for_departure(state, plan["id"], reason)

  defp reason_text(:instruction_onward_conflict),
    do: "Choose one shared onward port for this visit before purchases can resume"

  defp reason_text(:price_changed), do: "Waiting for the limit price"
  defp reason_text(:insufficient_cargo), do: "Waiting for cargo aboard"
  defp reason_text(:insufficient_supply), do: "Waiting for market supply"
  defp reason_text(:insufficient_demand), do: "Waiting for market demand or buyer funds"

  defp reason_text(:insufficient_cash),
    do: "Waiting for available company funds or unpaid costs to clear"

  defp reason_text(:instruction_budget_exhausted), do: "Purchase spending cap exhausted"

  defp reason_text({:purchase_voyage_funds, _, _, _}),
    do: "Waiting for funds after preserving onward voyage costs"

  defp reason_text(:purchase_destination_required), do: "Onward voyage is unavailable"
  defp reason_text(_), do: "Cargo is currently unavailable for trading at this port"
end
