defmodule TijaraTides.Domain.Services.LinkedOrders do
  @moduledoc "Atomic standing links between fixed route targets, remote orders and collection claims."
  alias TijaraTides.Domain.{
    AutomationWorld,
    State,
    OrderBookWorld,
    WarehouseWorld,
    OrderBook,
    CargoRules,
    Notices
  }

  alias TijaraTides.Domain.Services.Exchange

  def reconcile_edit(before, state, account, command, catalogue) do
    ship = command["ship"]

    old =
      State.entities(before, "route_rules")
      |> Map.values()
      |> Enum.filter(&(&1["ship_id"] == ship))

    state =
      Enum.reduce(old, state, fn rule, s ->
        current = State.get(s, "route_rules", rule["id"])

        if rule["linked_warehouse_id"] &&
             (is_nil(current) or current["linked_warehouse_id"] != rule["linked_warehouse_id"] or
                current["good"] != rule["good"]),
           do: remove(s, rule, "stop removed or link changed"),
           else: s
      end)

    rules =
      State.entities(state, "route_rules")
      |> Map.values()
      |> Enum.filter(&(&1["ship_id"] == ship and &1["linked_warehouse_id"] != nil))
      |> Enum.sort_by(& &1["id"])

    Enum.reduce_while(rules, {:ok, state}, fn rule, {:ok, s} ->
      previous = State.get(before, "route_rules", rule["id"])

      cond do
        rule == previous ->
          {:cont, {:ok, s}}

        not valid?(s, account, rule, catalogue) ->
          {:halt, {:error, :linked_order_invalid}}

        committed?(s, rule) ->
          {:halt, {:error, :route_stop_committed}}

        true ->
          case update_demand(s, rule, catalogue) do
            {:ok, next} ->
              case TijaraTides.Domain.ShipWorld.RoutePlans.reconcile_linked_target(
                     next,
                     rule,
                     catalogue
                   ) do
                {:ok, next} -> {:cont, {:ok, next}}
                error -> {:halt, error}
              end

            error ->
              {:halt, error}
          end
      end
    end)
  end

  defp valid?(state, account, rule, catalogue) do
    stop = State.get(state, "route_stops", rule["stop_id"])
    warehouse = State.get(state, "warehouses", rule["linked_warehouse_id"])

    rule["side"] == "buy" && rule["quantity_mode"] == "fixed" && rule["limit"] > 0 &&
      OrderBook.supported?(catalogue["goods"][rule["good"]]) && stop && warehouse &&
      TijaraTides.Domain.Warehouse.receiving_allowed?(
        WarehouseWorld.snapshot(warehouse),
        account["company_id"],
        stop["port"],
        catalogue["goods"][rule["good"]],
        state.clock_ms
      )
  end

  defp committed?(state, rule) do
    route = State.get(state, "ship_routes", rule["ship_id"])
    stop = State.get(state, "route_stops", rule["stop_id"])
    ship = State.get(state, "ships", rule["ship_id"])

    route && route["status"] != "draft" && route["cursor"] == stop["position"] &&
      route["phase"] != "arrival" && ship["status"] in ["loading", "unloading"]
  end

  defp update_demand(state, rule, catalogue) do
    link = State.get(state, "remote_links", rule["id"])

    if link && link["status"] != "active" do
      ship = State.get(state, "ships", rule["ship_id"])

      aboard =
        Enum.sum(
          for b <- ship["cargo"],
              b["good"] == rule["good"],
              CargoRules.qualifies?(
                b["expires_ms"],
                state.clock_ms,
                rule["min_remaining_ms"] || 0
              ),
              do: b["quantity"]
        )

      {:ok,
       WarehouseWorld.release_link_stock(
         state,
         ship["id"],
         rule["stop_id"],
         rule["good"],
         max(0, rule["quantity"] - aboard)
       )}
    else
      ship = State.get(state, "ships", rule["ship_id"])
      stop = State.get(state, "route_stops", rule["stop_id"])

      aboard =
        Enum.sum(
          for b <- ship["cargo"],
              b["good"] == rule["good"],
              CargoRules.qualifies?(
                b["expires_ms"],
                state.clock_ms,
                rule["min_remaining_ms"] || 0
              ),
              do: b["quantity"]
        )

      held =
        Enum.sum(
          for {_, r} <- State.entities(state, "warehouse_reservations"),
              r["ship_id"] == ship["id"],
              r["stop_id"] == stop["id"],
              r["good"] == rule["good"],
              String.starts_with?(r["id"], "linked:"),
              do: r["quantity"]
        )

      target = max(0, rule["quantity"] - aboard)

      state =
        WarehouseWorld.release_link_stock(state, ship["id"], stop["id"], rule["good"], target)

      owned =
        State.owned(state, "warehouses", "company_id", rule["company_id"])
        |> Enum.filter(
          &(&1["port"] == stop["port"] and
              &1["expires_ms"] + (&1["grace_ms"] || 43_200_000) > state.clock_ms)
        )
        |> Enum.map(fn row ->
          w = WarehouseWorld.fetch(state, row["id"])

          fresh =
            Enum.sum(
              for b <- w.cargo,
                  b.good == rule["good"],
                  CargoRules.qualifies?(
                    b.expires_ms,
                    state.clock_ms,
                    rule["min_remaining_ms"] || 0
                  ),
                  do: b.quantity
            )

          other = WarehouseWorld.reserved_quantity(state, w, "stock", rule["good"], ship["id"])
          max(0, fresh - other)
        end)
        |> Enum.sum()

      # Completed demand is never replenished merely because its cargo aged or disappeared.
      lost = max(0, if(link, do: link["filled"], else: 0) - held)
      demand = max(0, target - owned - lost)
      order = link && OrderBookWorld.fetch(state, link["order_id"])

      cond do
        demand == 0 ->
          next = if(order, do: cancel_order(state, order), else: state)

          {:ok,
           if(link,
             do: AutomationWorld.close_link(next, link, "active"),
             else: AutomationWorld.open_link(next, rule, "linked:" <> rule["id"] <> ":0", 0)
           )}

        order && demand == order.quantity && rule["limit"] == order.price &&
            (rule["min_remaining_ms"] || 0) == order.min_remaining_ms ->
          {:ok, state}

        order ->
          case Exchange.amend(
                 state,
                 owner(state, rule),
                 %{
                   "order" => order.id,
                   "quantity" => demand,
                   "price" => rule["limit"],
                   "min_remaining_ms" => rule["min_remaining_ms"] || 0
                 },
                 catalogue
               ) do
            {:ok, s, _} -> {:ok, s}
            error -> error
          end

        true ->
          open(state, rule, catalogue, demand, link)
      end
    end
  end

  defp open(state, rule, catalogue, quantity, previous) do
    generation = if(previous, do: previous["generation"] + 1, else: 0)
    id = "linked:" <> rule["id"] <> ":" <> to_string(generation)
    state = AutomationWorld.open_link(state, rule, id, generation)

    state =
      if previous,
        do:
          AutomationWorld.record_remote_fill(
            state,
            State.get(state, "remote_links", rule["id"]),
            previous["filled"]
          ),
        else: state

    case Exchange.place(
           state,
           owner(state, rule),
           %{
             "warehouse" => rule["linked_warehouse_id"],
             "side" => "buy",
             "good" => rule["good"],
             "quantity" => quantity,
             "price" => rule["limit"],
             "min_remaining_ms" => rule["min_remaining_ms"] || 0
           },
           id,
           catalogue
         ) do
      {:ok, s, _} -> {:ok, s}
      error -> error
    end
  end

  def handover(state, ship_id) do
    ship = State.get(state, "ships", ship_id)
    route = State.get(state, "ship_routes", ship_id)

    stop =
      if route,
        do: Enum.at(TijaraTides.Domain.ShipWorld.route_stops(state, ship_id), route["cursor"])

    if stop && not route["visit_finished"],
      do: close_at(state, ship_id, ship["port"], "handed_over", false, stop["id"]),
      else: state
  end

  def skip(state, ship, stop),
    do: close_at(state, ship, stop["port"], "skipped", false, stop["id"])

  def finish_visit(state, ship, stop, catalogue) do
    rules =
      State.entities(state, "route_rules")
      |> Map.values()
      |> Enum.filter(
        &(&1["ship_id"] == ship and &1["stop_id"] == stop and &1["linked_warehouse_id"])
      )
      |> Enum.sort_by(& &1["id"])

    Enum.reduce(rules, state, fn rule, s ->
      link = State.get(s, "remote_links", rule["id"])
      s = if link, do: close(s, link, "finished", true), else: s
      # The standing link gets a new cycle even if backing is presently unaffordable.
      generation = if(link, do: link["generation"] + 1, else: 0)

      s =
        AutomationWorld.open_link(
          s,
          rule,
          "linked:" <> rule["id"] <> ":" <> to_string(generation),
          generation
        )

      case update_demand(s, rule, catalogue) do
        {:ok, next} ->
          next

        {:error, _} ->
          Notices.notice(
            s,
            owner(s, rule)["id"],
            "link:" <> rule["id"],
            {"linked.unfunded", %{"port" => State.get(s, "route_stops", stop)["port"]}}
          )
      end
    end)
  end

  def advance(state, catalogue) do
    state = reconcile(state)

    Enum.reduce(
      State.entities(state, "remote_links") |> Enum.sort_by(&elem(&1, 0)),
      state,
      fn {id, _}, s ->
        link = State.get(s, "remote_links", id)
        rule = State.get(s, "route_rules", id)
        ship = link && State.get(s, "ships", link["ship_id"])
        route = link && State.get(s, "ship_routes", link["ship_id"])
        stop = link && State.get(s, "route_stops", link["stop_id"])

        cond do
          is_nil(link) or link["status"] != "active" ->
            s

          route && stop && route["cursor"] == stop["position"] && not route["visit_finished"] &&
              route["wait_timed_out"] ->
            close(s, link, "wait limit elapsed", true)

          ship && ship["berth_granted_ms"] && route && not route["visit_finished"] &&
              stop["position"] == route["cursor"] ->
            handover(s, ship["id"])

          true ->
            case update_demand(s, rule, catalogue) do
              {:ok, next} -> next
              {:error, _} -> s
            end
        end
      end
    )
  end

  def reconcile(state) do
    Enum.reduce(State.entities(state, "remote_links"), state, fn {_, link}, s ->
      rule = State.get(s, "route_rules", link["id"])
      company = State.get(s, "companies", link["company_id"])

      if is_nil(rule) or company["bankruptcy_ms"] != nil,
        do: close(s, link, "removed", true) |> AutomationWorld.remove_link(link["id"]),
        else: s
    end)
  end

  def remove_ship(state, ship) do
    Enum.reduce(State.entities(state, "remote_links"), state, fn {_, link}, s ->
      if link["ship_id"] == ship,
        do: close(s, link, "removed", true) |> AutomationWorld.remove_link(link["id"]),
        else: s
    end)
  end

  defp remove(state, rule, reason) do
    link = State.get(state, "remote_links", rule["id"])

    if link,
      do: close(state, link, reason, true) |> AutomationWorld.remove_link(link["id"]),
      else: state
  end

  defp close_at(state, ship, port, status, release, stop_id) do
    Enum.reduce(State.entities(state, "remote_links"), state, fn {_, link}, s ->
      stop = State.get(s, "route_stops", link["stop_id"])

      if link["ship_id"] == ship && stop && stop["port"] == port &&
           (is_nil(stop_id) || stop["id"] == stop_id) && link["status"] == "active",
         do: close(s, link, status, release),
         else: s
    end)
  end

  defp close(state, link, status, release) do
    order = OrderBookWorld.fetch(state, link["order_id"])
    stop = State.get(state, "route_stops", link["stop_id"])

    stored =
      Enum.sum(
        for {_, r} <- State.entities(state, "warehouse_reservations"),
            r["ship_id"] == link["ship_id"],
            r["stop_id"] == link["stop_id"],
            r["good"] == link["good"],
            String.starts_with?(r["id"], "linked:"),
            do: r["quantity"]
      )

    reason =
      case status do
        "handed_over" -> "Handed over at berth"
        "skipped" -> "Purchases skipped for this visit"
        "finished" -> "Visit finished"
        "wait limit elapsed" -> "Maximum wait elapsed"
        _ -> "Collection stop or link removed"
      end

    s = AutomationWorld.close_link(state, link, status)
    s = if order, do: cancel_order(s, order), else: s

    s =
      if release,
        do: WarehouseWorld.release_link_stock(s, link["ship_id"], link["stop_id"], link["good"]),
        else: s

    if order || (release && stored > 0) do
      company = State.get(s, "companies", link["company_id"])
      ship = State.get(s, "ships", link["ship_id"])

      Notices.notice(
        s,
        company["account_id"],
        "link:" <> link["id"],
        {"linked.cancelled",
         %{
           "ship" => if(ship, do: ship["name"], else: link["ship_id"]),
           "port" => if(stop, do: stop["port"], else: link["port"]),
           "cargo" => link["good"],
           "quantity" => if(order, do: order.quantity, else: 0),
           "refund" => if(order, do: order.quantity * order.price, else: 0),
           "filled" => stored,
           "reason" => reason
         }}
      )
    else
      s
    end
  end

  defp cancel_order(state, order) do
    {:ok, next, _} = Exchange.cancel(state, %{"company_id" => order.company_id}, order.id)
    next
  end

  defp owner(state, rule),
    do:
      State.get(
        state,
        "accounts",
        State.get(state, "companies", rule["company_id"])["account_id"]
      )
      |> Map.put("linked_operation", true)
end
