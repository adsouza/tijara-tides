defmodule TijaraTides.Domain.AutomationWorld do
  @moduledoc "Owns linked-order cycles, visit cash reservations and departure requests."
  alias TijaraTides.Domain.{State, CompanyFinanceWorld, VisitBudget, DepartureRequest, RemoteLink}

  def open_link(state, rule, order_id, generation) do
    port = State.get(state, "route_stops", rule["stop_id"])["port"]
    store_link(state, RemoteLink.new(rule, order_id, generation, port))
  end

  def record_remote_fill(state, row, quantity),
    do: store_link(state, RemoteLink.fill(RemoteLink.Rows.decode(row), quantity))

  def close_link(state, row, status),
    do: store_link(state, RemoteLink.close(RemoteLink.Rows.decode(row), status))

  def remove_link(state, id), do: State.delete(state, "remote_links", id)

  def reserve_visit(state, spec, amount, skip) do
    unless State.get(state, "visit_budgets", spec.id) == nil,
      do: raise(ArgumentError, "Visit budget already funded")

    model = VisitBudget.new(spec, amount, skip)
    state |> move_cash(model.company_id, model.remaining, "visit_budget") |> store_budget(model)
  end

  def resize_visit(state, row, amount) do
    budget = VisitBudget.Rows.decode(row)
    company = State.get(state, "companies", budget.company_id)

    with {:ok, model, delta} <-
           VisitBudget.resize(
             budget,
             amount,
             company["cash"] - company["reserved"],
             company["unpaid"]
           ) do
      {:ok, state |> move_cash(model.company_id, delta, "visit_budget") |> store_budget(model)}
    end
  end

  def consume_visit(state, id, amount) do
    case State.get(state, "visit_budgets", id) do
      nil -> raise(ArgumentError, "Purchase exceeds reserved visit budget")
      row -> store_budget(state, VisitBudget.consume(VisitBudget.Rows.decode(row), amount))
    end
  end

  def release_visit(state, row) do
    model = VisitBudget.Rows.decode(row)

    state
    |> move_cash(model.company_id, -model.remaining, "visit_budget_release")
    |> State.delete("visit_budgets", model.id)
  end

  def request(state, spec, policy, required),
    do: store_request(state, DepartureRequest.new(spec, policy, required, state.clock_ms))

  def accumulate(state, row, amount, deadline) do
    model = DepartureRequest.accumulate(DepartureRequest.Rows.decode(row), amount, deadline)
    state |> move_cash(model.company_id, amount, "departure_accumulation") |> store_request(model)
  end

  def release_accumulation(state, row, cooldown \\ nil) do
    request = DepartureRequest.Rows.decode(row)

    state
    |> move_cash(request.company_id, -request.accumulated, "departure_accumulation_release")
    |> store_request(DepartureRequest.release(request, cooldown))
  end

  def abandon_request(state, row),
    do: state |> release_accumulation(row) |> State.delete("departure_requests", row["id"])

  def complete_request(state, id), do: State.delete(state, "departure_requests", id)

  defp store_link(state, model),
    do: State.put(state, "remote_links", model.id, RemoteLink.Rows.encode(model))

  defp store_budget(state, model),
    do: State.put(state, "visit_budgets", model.id, VisitBudget.Rows.encode(model))

  defp store_request(state, model),
    do: State.put(state, "departure_requests", model.id, DepartureRequest.Rows.encode(model))

  def budget(state, ship, port) do
    State.owned(state, "visit_budgets", "company_id", ship["company_id"])
    |> Enum.find(
      &(&1["ship_id"] == ship["id"] and &1["port"] == port and current_visit?(state, &1))
    )
  end

  @doc "A stop reservation belongs only to its selected visit, including the inbound voyage."
  def current_visit?(state, row) do
    if row["stop_id"] do
      route = State.get(state, "ship_routes", row["ship_id"])
      stop = State.get(state, "route_stops", row["stop_id"])
      ship = State.get(state, "ships", row["ship_id"])

      not is_nil(route) and not is_nil(stop) and not is_nil(ship) and
        route["status"] != "draft" and not route["visit_finished"] and
        not route["wait_timed_out"] and row["visit"] == route["visit"] and
        stop["ship_id"] == row["ship_id"] and stop["position"] == route["cursor"] and
        stop["port"] == row["port"] and
        if(ship["status"] == "sailing", do: ship["destination"], else: ship["port"]) ==
          row["port"]
    else
      true
    end
  end

  def release_ship(state, id) do
    state =
      Enum.reduce(State.entities(state, "visit_budgets"), state, fn {_, row}, s ->
        if row["ship_id"] == id, do: release_visit(s, row), else: s
      end)

    case State.get(state, "departure_requests", id) do
      nil -> state
      row -> abandon_request(state, row)
    end
  end

  defp move_cash(state, _company, 0, _kind), do: state

  defp move_cash(state, company, amount, kind),
    do:
      CompanyFinanceWorld.post(state, company, kind, [
        {"cash_available", -amount},
        {"cash_reserved", amount}
      ])
end
