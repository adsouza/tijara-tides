defmodule TijaraTides.Domain.Services.DepartureFunding do
  @moduledoc "Oldest-affordable departures with atomic fuel/budget funding and bounded accumulation."
  alias TijaraTides.Domain.{State, Automation, AutomationWorld, ShipWorld, Fleet, Notices}
  alias TijaraTides.Domain.{AccountWorld, ChangeSet}
  alias TijaraTides.Domain.Services.{FinancialSettlement, LinkedOrders}

  defp requirement(quote, spec, policy),
    do:
      Automation.requirement(
        quote["fuel"] + quote["canal_fees"],
        if(spec.pre_reserved, do: nil, else: spec.configured),
        policy
      )

  @doc "Manual departures still honor an explicitly configured advance budget."
  def manual_sail(state, account, ship_id, destination, limit, catalogue),
    do:
      settled(
        state,
        catalogue,
        &fund_manual_sail(&1, account, ship_id, destination, limit, catalogue)
      )

  defp fund_manual_sail(state, account, ship_id, destination, limit, catalogue) do
    state = FinancialSettlement.settle(state, [account["company_id"]])

    ship = State.get(state, "ships", ship_id)

    if ship && is_binary(destination) && ship["company_id"] == account["company_id"] do
      spec = spec(state, ship, destination)
      amount = spec.configured
      company = State.get(state, "companies", account["company_id"])

      cond do
        amount == nil or spec.pre_reserved ->
          Fleet.sail(state, account, ship_id, destination, limit, catalogue)

        company["cash"] - company["reserved"] < amount or company["unpaid"] > 0 ->
          {:error, :insufficient_cash}

        true ->
          candidate = AutomationWorld.reserve_visit(state, spec, amount, false)
          Fleet.sail(candidate, account, ship_id, destination, limit, catalogue)
      end
    else
      Fleet.sail(state, account, ship_id, destination, limit, catalogue)
    end
  end

  def configure_visit(state, account, command, catalogue) do
    ship = State.get(state, "ships", command["ship"])
    amount = command["amount"]
    stop = command["stop"] && State.get(state, "route_stops", command["stop"])
    port = if stop, do: stop["port"], else: command["port"]
    id = if stop, do: stop["id"], else: to_string(command["ship"]) <> "|" <> to_string(port)
    plan = State.get(state, "visit_plans", id)
    route = ship && State.get(state, "ship_routes", ship["id"])

    current =
      stop && route && route["status"] != "draft" &&
        route["cursor"] == stop["position"] && not route["visit_finished"] &&
        not route["wait_timed_out"]

    reserve_now = is_nil(stop) || current
    company = ship && State.get(state, "companies", ship["company_id"])

    cond do
      is_nil(ship) or ship["company_id"] != account["company_id"] ->
        {:error, :instruction_ship_not_owned}

      not is_nil(amount) and (not is_integer(amount) or amount < 0 or amount > 1_000_000_000_000) ->
        {:error, :instruction_budget_invalid}

      stop && stop["ship_id"] != ship["id"] ->
        {:error, :route_port_invalid}

      is_nil(stop) && (is_nil(plan) or plan["ship_id"] != ship["id"]) ->
        {:error, :instruction_destination_invalid}

      reserve_now && amount != nil && is_nil(State.get(state, "visit_budgets", id)) &&
          (company["unpaid"] > 0 || company["cash"] - company["reserved"] < amount) ->
        {:error, :insufficient_cash}

      true ->
        row = State.get(state, "visit_budgets", id)

        result =
          cond do
            row && is_nil(amount) ->
              {:ok, AutomationWorld.release_visit(state, row)}

            row ->
              AutomationWorld.resize_visit(state, row, amount)

            reserve_now && amount != nil ->
              {:ok,
               AutomationWorld.reserve_visit(
                 state,
                 %{
                   id: id,
                   ship_id: ship["id"],
                   company_id: ship["company_id"],
                   stop_id: stop && stop["id"],
                   port: port,
                   configured: amount,
                   visit: if(route, do: route["visit"], else: 0)
                 },
                 amount,
                 false
               )}

            true ->
              {:ok, state}
          end

        with {:ok, s} <- result do
          s = TijaraTides.Domain.ShipWorld.set_advance_budget(s, id, stop != nil, amount)
          {:ok, settle_ships(state, s, catalogue), %{}}
        end
    end
  end

  @doc "Fund the current unfinished visit when a route first starts or resumes."
  def fund_current_visit(state, ship_id) do
    route = State.get(state, "ship_routes", ship_id)
    ship = State.get(state, "ships", ship_id)
    stop = route && Enum.at(ShipWorld.route_stops(state, ship_id), route["cursor"])
    company = ship && State.get(state, "companies", ship["company_id"])

    if stop && route["status"] == "running" && not route["visit_finished"] &&
         not route["wait_timed_out"] && stop["advance_budget"] != nil &&
         is_nil(State.get(state, "visit_budgets", stop["id"])) do
      amount = stop["advance_budget"]

      if company["unpaid"] > 0 || company["cash"] - company["reserved"] < amount do
        {:error, :insufficient_cash}
      else
        {:ok,
         AutomationWorld.reserve_visit(
           state,
           %{
             id: stop["id"],
             ship_id: ship_id,
             company_id: ship["company_id"],
             stop_id: stop["id"],
             port: stop["port"],
             configured: amount,
             visit: route["visit"]
           },
           amount,
           false
         )}
      end
    else
      {:ok, state}
    end
  end

  def advance(state, catalogue, company_id \\ :all) do
    state = state |> finish_visits(catalogue) |> mark_pending_departures()

    plans =
      ready_plans(state) |> Enum.filter(&(company_id == :all or &1["company_id"] == company_id))

    state =
      Enum.reduce(plans, state, fn plan, s ->
        ship = State.get(s, "ships", plan["ship_id"])
        spec = spec(s, ship, plan["onward"])
        quote = Fleet.voyage_quote(ship, plan["onward"], catalogue, state.clock_ms)
        company = State.get(s, "companies", ship["company_id"])
        account = State.get(s, "accounts", company["account_id"])
        policy = account["funding_policy"] || "wait"

        if quote && quote["duration_ms"] <= 86_400_000 && company["bankruptcy_ms"] == nil do
          required =
            requirement(quote, spec, policy)

          if State.get(s, "departure_requests", ship["id"]),
            do: s,
            else: AutomationWorld.request(s, spec, policy, required)
        else
          ShipWorld.wait_for_departure(
            s,
            plan["id"],
            cond do
              company["bankruptcy_ms"] != nil -> "Company is in receivership"
              is_nil(quote) -> "No sea route is available to the onward destination"
              true -> "The onward voyage exceeds the maximum duration"
            end
          )
        end
      end)

    State.entities(state, "departure_requests")
    |> Map.values()
    |> Enum.filter(&(company_id == :all or &1["company_id"] == company_id))
    |> Enum.group_by(& &1["company_id"])
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce(state, fn {company, _}, s -> allocate(s, company, catalogue) end)
  end

  @automation_kinds ~w(ships ship_routes route_stops ship_instructions visit_plans visit_budgets departure_requests)

  @doc """
  Funding consequences of a transition: a budget stays reserved only for the visit it
  funds, and a departure request only while it still describes the next departure.
  Only ships whose automation rows the transition changed are revalidated.
  """
  def settle_ships(before, state, catalogue),
    do: revalidate(state, changed_ships(before, state), catalogue)

  defp changed_ships(before, state) do
    for {{kind, id}, _} <- ChangeSet.since(before, state),
        kind in @automation_kinds,
        source <- [before, state],
        row = get_in(source, [:entities, kind, id]),
        row != nil,
        uniq: true,
        do: if(kind in ["ships", "ship_routes"], do: id, else: row["ship_id"])
  end

  def revalidate(state, [], _catalogue), do: state

  def revalidate(state, ship_ids, catalogue) do
    state =
      Enum.reduce(Enum.sort(ship_ids), state, fn id, s ->
        Enum.reduce(ship_budgets(s, id), s, fn row, s ->
          if budget_valid?(s, row), do: s, else: AutomationWorld.release_visit(s, row)
        end)
      end)

    revalidate_requests(state, ship_ids, catalogue)
  end

  defp ship_budgets(state, ship_id) do
    case State.get(state, "ships", ship_id) do
      nil ->
        State.entities(state, "visit_budgets")
        |> Map.values()
        |> Enum.filter(&(&1["ship_id"] == ship_id))

      ship ->
        State.owned(state, "visit_budgets", "company_id", ship["company_id"])
        |> Enum.filter(&(&1["ship_id"] == ship_id))
    end
  end

  defp budget_valid?(s, row) do
    ship = State.get(s, "ships", row["ship_id"])
    stop = row["stop_id"] && State.get(s, "route_stops", row["stop_id"])
    plan = State.get(s, "visit_plans", row["id"])
    route = ship && State.get(s, "ship_routes", ship["id"])
    company = State.get(s, "companies", row["company_id"])

    ship && ship["company_id"] == row["company_id"] && company["bankruptcy_ms"] == nil &&
      if(row["stop_id"], do: stop && route && route["status"] != "draft", else: plan != nil) &&
      AutomationWorld.current_visit?(s, row) &&
      not visit_ended?(s, ship, route, row)
  end

  defp revalidate_requests(state, ship_ids, catalogue) do
    rows =
      for id <- Enum.sort(ship_ids), row = State.get(state, "departure_requests", id), do: row

    if rows == [] do
      state
    else
      plans_by_ship = Map.new(ready_plans(state), &{&1["ship_id"], &1})

      Enum.reduce(rows, state, fn row, s ->
        if request_valid?(s, row, plans_by_ship[row["ship_id"]], catalogue),
          do: s,
          else: AutomationWorld.abandon_request(s, row)
      end)
    end
  end

  defp request_valid?(s, row, plan, catalogue) do
    company = State.get(s, "companies", row["company_id"])
    account = State.get(s, "accounts", company["account_id"])

    case departure_terms(s, row, plan, catalogue) do
      nil ->
        false

      {current, quote} ->
        row["policy"] == (account["funding_policy"] || "wait") &&
          row["required"] == requirement(quote, current, row["policy"])
    end
  end

  # The request still describes the ship's next departure, whatever its price.
  defp departure_terms(s, row, plan, catalogue) do
    ship = State.get(s, "ships", row["ship_id"])
    company = State.get(s, "companies", row["company_id"])
    current = if ship && plan, do: spec(s, ship, plan["onward"])
    quote = if ship && plan, do: Fleet.voyage_quote(ship, plan["onward"], catalogue, s.clock_ms)

    if current && quote && company["bankruptcy_ms"] == nil &&
         row["destination"] == current.port && row["stop_id"] == current.stop_id &&
         row["visit"] == current.visit && row["configured"] == current.configured,
       do: {current, quote}
  end

  @doc "A policy change re-prices waiting requests in place, keeping their waiting age."
  def set_policy(state, account, policy, catalogue) do
    with {:ok, changed, reply} <- AccountWorld.set_funding_policy(state, account, policy) do
      rows = State.owned(changed, "departure_requests", "company_id", account["company_id"])
      plans_by_ship = Map.new(ready_plans(changed), &{&1["ship_id"], &1})

      changed =
        Enum.reduce(Enum.sort_by(rows, & &1["id"]), changed, fn row, s ->
          case departure_terms(s, row, plans_by_ship[row["ship_id"]], catalogue) do
            nil ->
              AutomationWorld.abandon_request(s, row)

            {current, quote} ->
              AutomationWorld.reprice_request(s, row, policy, requirement(quote, current, policy))
          end
        end)

      {:ok, changed, reply}
    end
  end

  @doc "Ship transitions whose funding consequences this coordinator owns."
  def reroute(state, account, ship, destination, limit, catalogue),
    do:
      settled(state, catalogue, &Fleet.reroute(&1, account, ship, destination, limit, catalogue))

  def change_onward(state, account, ship, port, onward, catalogue, auto_depart),
    do:
      settled(
        state,
        catalogue,
        &ShipWorld.change_onward(&1, account, ship, port, onward, catalogue, auto_depart)
      )

  def cancel_instruction(state, account, id, catalogue),
    do: settled(state, catalogue, &ShipWorld.cancel_instruction(&1, account, id, catalogue))

  def expire_instructions(state, catalogue),
    do: settle_ships(state, ShipWorld.expire_instructions(state, catalogue), catalogue)

  def expire_route_waits(state, catalogue),
    do: settle_ships(state, ShipWorld.expire_route_waits(state, catalogue), catalogue)

  def prepare_visits(state, catalogue),
    do: settle_ships(state, ShipWorld.prepare_visits(state, catalogue), catalogue)

  defp settled(state, catalogue, transition) do
    with {:ok, changed, reply} <- transition.(state),
         do: {:ok, settle_ships(state, changed, catalogue), reply}
  end

  defp visit_ended?(state, ship, route, row) do
    if row["stop_id"] do
      current = route && Enum.at(ShipWorld.route_stops(state, row["ship_id"]), route["cursor"])
      current && current["id"] == row["stop_id"] && route["wait_timed_out"]
    else
      orders =
        State.entities(state, "ship_instructions")
        |> Map.values()
        |> Enum.filter(&(&1["ship_id"] == row["ship_id"] && &1["port"] == row["port"]))

      ship && ship["status"] not in ["loading", "unloading"] && orders != [] &&
        Enum.all?(orders, &(&1["status"] not in ["planned", "waiting"]))
    end
  end

  defp allocate(state, company_id, catalogue) do
    settings = Automation.settings(catalogue)
    state = FinancialSettlement.settle(state, [company_id])
    # Readiness changes with handling, berths and pending orders; check it where it is used.
    state =
      revalidate_requests(
        state,
        Enum.map(requests(state, company_id), & &1["ship_id"]),
        catalogue
      )

    state =
      Enum.reduce(requests(state, company_id), state, fn row, s ->
        if row["window_deadline_ms"] && row["window_deadline_ms"] <= s.clock_ms do
          s
          |> AutomationWorld.release_accumulation(row, s.clock_ms + settings["cooldown_ms"])
          |> FinancialSettlement.settle([company_id])
          |> Notices.notice(
            State.get(s, "companies", company_id)["account_id"],
            "funding-timeout:" <> row["id"],
            {"funding.timeout", %{"ship" => State.get(s, "ships", row["id"])["name"]}}
          )
        else
          s
        end
      end)

    accumulating = Enum.find(requests(state, company_id), &(&1["window_deadline_ms"] != nil))

    if accumulating do
      accumulate(state, accumulating, catalogue, settings)
    else
      state =
        Enum.reduce(requests(state, company_id), state, fn row, s ->
          attempt(s, row, catalogue)
        end)

      eligible =
        Enum.find(
          requests(state, company_id),
          &(&1["blocked_ms"] + settings["wait_ms"] <= state.clock_ms &&
              (&1["cooldown_ms"] || 0) <= state.clock_ms)
        )

      if eligible, do: accumulate(state, eligible, catalogue, settings), else: state
    end
  end

  defp requests(state, company),
    do:
      State.owned(state, "departure_requests", "company_id", company)
      |> Enum.sort_by(&{&1["blocked_ms"], &1["id"]})

  defp available(state, company) do
    row = State.get(state, "companies", company)
    if row["unpaid"] > 0, do: 0, else: max(0, row["cash"] - row["reserved"])
  end

  defp accumulate(state, row, catalogue, settings) do
    n = min(row["required"] - row["accumulated"], available(state, row["company_id"]))
    state = AutomationWorld.accumulate(state, row, n, state.clock_ms + settings["window_ms"])
    row = State.get(state, "departure_requests", row["id"])

    if row["accumulated"] == row["required"],
      do: attempt(state, row, catalogue),
      else: blocked(state, row)
  end

  defp attempt(state, row, catalogue) do
    if available(state, row["company_id"]) + row["accumulated"] >= row["required"] &&
         State.get(state, "companies", row["company_id"])["unpaid"] == 0 do
      ship = State.get(state, "ships", row["ship_id"])
      quote = Fleet.voyage_quote(ship, row["destination"], catalogue, state.clock_ms)
      spec = spec(state, ship, row["destination"])
      # Conversion and Fleet's ordinary fuel reservation are one pure candidate,
      # returned only if departure succeeds. The old accumulation is not spent twice.
      candidate = AutomationWorld.release_accumulation(state, row)
      free = available(candidate, row["company_id"]) - quote["fuel"] - quote["canal_fees"]

      effective =
        if spec.pre_reserved || free >= (spec.configured || 0), do: "wait", else: row["policy"]

      skip = effective == "skip"
      amount = Automation.purchase_amount(spec.configured, effective, free)

      candidate =
        if not spec.pre_reserved && (spec.configured != nil or skip),
          do: AutomationWorld.reserve_visit(candidate, spec, amount, skip),
          else: candidate

      candidate =
        if skip && spec.stop_id,
          do:
            LinkedOrders.skip(
              candidate,
              ship["id"],
              State.get(candidate, "route_stops", spec.stop_id)
            ),
          else: candidate

      account =
        State.get(
          candidate,
          "accounts",
          State.get(candidate, "companies", row["company_id"])["account_id"]
        )

      case Fleet.sail(
             candidate,
             account,
             ship["id"],
             row["destination"],
             quote["fuel"],
             catalogue
           ) do
        {:ok, changed, _} ->
          changed
          |> AutomationWorld.complete_request(row["id"])
          |> then(&settle_ships(state, &1, catalogue))
          |> Notices.notice(
            account["id"],
            "auto-depart:" <> ship["id"] <> "|" <> ship["port"],
            {"ship.departed",
             %{
               "ship" => ship["name"],
               "port" => ship["port"],
               "destination" => row["destination"]
             }}
          )

        {:error, _} ->
          blocked(state, row)
      end
    else
      blocked(state, row)
    end
  end

  defp blocked(state, row) do
    ship = State.get(state, "ships", row["ship_id"])
    plan = State.get(state, "visit_plans", ship["id"] <> "|" <> ship["port"])

    reason =
      if State.get(state, "companies", row["company_id"])["unpaid"] > 0,
        do: "Waiting for unpaid operating costs to clear",
        else:
          if(row["configured"] == nil,
            do: "Waiting for available funds for fuel and canal fees",
            else: "Waiting for fuel and the configured purchase budget"
          )

    if plan, do: ShipWorld.wait_for_departure(state, plan["id"], reason), else: state
  end

  def spec(state, ship, destination) do
    route = State.get(state, "ship_routes", ship["id"])
    stops = ShipWorld.route_stops(state, ship["id"])
    stop = if route && stops != [], do: Enum.at(stops, rem(route["cursor"] + 1, length(stops)))
    stop = if stop && stop["port"] == destination, do: stop
    plan = State.get(state, "visit_plans", ship["id"] <> "|" <> destination)

    id = if(stop, do: stop["id"], else: ship["id"] <> "|" <> destination)
    pre_reserved = is_nil(stop) && State.get(state, "visit_budgets", id) != nil

    %{
      pre_reserved: pre_reserved,
      id: if(stop, do: stop["id"], else: ship["id"] <> "|" <> destination),
      ship_id: ship["id"],
      company_id: ship["company_id"],
      stop_id: stop && stop["id"],
      port: destination,
      configured: if(stop, do: stop["advance_budget"], else: plan && plan["advance_budget"]),
      visit: if(route, do: route["visit"] + 1, else: 0)
    }
  end

  defp mark_pending_departures(state) do
    pending_visits = pending_visits(state)

    Enum.reduce(State.entities(state, "visit_plans"), state, fn {_, plan}, s ->
      ship = State.get(s, "ships", plan["ship_id"])

      pending = MapSet.member?(pending_visits, {plan["ship_id"], plan["port"]})

      cond do
        not plan["auto_depart"] or is_nil(ship) or ship["port"] != plan["port"] or
            not ShipWorld.automation_enabled?(s, ship["id"]) ->
          s

        ship["status"] in ["loading", "unloading"] ->
          ShipWorld.wait_for_departure(s, plan["id"], "Waiting for cargo handling to finish")

        ship["status"] == "docked" && (pending || ship["pending_side"] != nil) ->
          ShipWorld.wait_for_departure(
            s,
            plan["id"],
            "Waiting for cargo orders to be filled or cancelled"
          )

        true ->
          s
      end
    end)
  end

  defp pending_visits(state),
    do:
      State.entities(state, "ship_instructions")
      |> Map.values()
      |> Enum.filter(&(&1["status"] in ["planned", "waiting"]))
      |> MapSet.new(&{&1["ship_id"], &1["port"]})

  defp ready_plans(state) do
    pending = pending_visits(state)

    State.entities(state, "visit_plans")
    |> Map.values()
    |> Enum.filter(fn plan ->
      ship = State.get(state, "ships", plan["ship_id"])

      plan["auto_depart"] && ship && ship["port"] == plan["port"] && ship["status"] == "docked" &&
        ship["pending_side"] == nil && ShipWorld.automation_enabled?(state, ship["id"]) &&
        not MapSet.member?(pending, {ship["id"], ship["port"]})
    end)
    |> Enum.sort_by(& &1["ship_id"])
  end

  def finish_visits(state, catalogue) do
    pending_ships = pending_visits(state) |> MapSet.new(&elem(&1, 0))

    Enum.reduce(State.entities(state, "ship_routes"), state, fn {id, route}, s ->
      ship = State.get(s, "ships", id)

      pending = MapSet.member?(pending_ships, id)

      if route["status"] != "draft" && route["phase"] == "buying" && not route["visit_finished"] &&
           ship && ship["status"] == "docked" && not pending do
        stop = Enum.at(ShipWorld.route_stops(s, id), route["cursor"])
        budget = AutomationWorld.budget(s, ship, ship["port"])
        s = if budget, do: AutomationWorld.release_visit(s, budget), else: s

        s
        |> ShipWorld.finish_route_visit(id)
        |> LinkedOrders.finish_visit(id, stop["id"], catalogue)
      else
        s
      end
    end)
    |> finish_single_visits()
  end

  defp finish_single_visits(state) do
    pending_visits = pending_visits(state)

    Enum.reduce(State.entities(state, "visit_budgets"), state, fn {_, row}, s ->
      ship = State.get(s, "ships", row["ship_id"])

      pending = MapSet.member?(pending_visits, {row["ship_id"], row["port"]})

      if is_nil(row["stop_id"]) && ship && ship["port"] == row["port"] &&
           ship["status"] == "docked" && not pending,
         do: AutomationWorld.release_visit(s, row),
         else: s
    end)
  end
end
