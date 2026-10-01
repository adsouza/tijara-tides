defmodule TijaraTides.Domain.AutomationWorld do
  @moduledoc "Owns linked-order cycles, visit cash reservations and departure requests."
  alias TijaraTides.Domain.{State, CompanyFinanceWorld}

  def open_link(state, rule, order_id, generation) do
    State.put(state, "remote_links", rule["id"], %{
      "id" => rule["id"],
      "company_id" => rule["company_id"],
      "ship_id" => rule["ship_id"],
      "stop_id" => rule["stop_id"],
      "good" => rule["good"],
      "warehouse_id" => rule["linked_warehouse_id"],
      "port" => State.get(state, "route_stops", rule["stop_id"])["port"],
      "order_id" => order_id,
      "generation" => generation,
      "filled" => 0,
      "status" => "active"
    })
  end

  def record_remote_fill(state, link, quantity),
    do:
      State.put(state, "remote_links", link["id"], %{link | "filled" => link["filled"] + quantity})

  def close_link(state, link, status),
    do: State.put(state, "remote_links", link["id"], %{link | "status" => status})

  def remove_link(state, id), do: State.delete(state, "remote_links", id)

  def reserve_visit(state, spec, amount, skip) do
    unless State.get(state, "visit_budgets", spec.id) == nil,
      do: raise(ArgumentError, "Visit budget already funded")

    amount = amount || 0

    state
    |> move_cash(spec.company_id, amount, "visit_budget")
    |> State.put("visit_budgets", spec.id, %{
      "id" => spec.id,
      "company_id" => spec.company_id,
      "ship_id" => spec.ship_id,
      "stop_id" => spec.stop_id,
      "port" => spec.port,
      "amount" => amount,
      "remaining" => amount,
      "strict" => spec.configured != nil,
      "skip" => skip,
      "visit" => spec.visit
    })
  end

  def resize_visit(state, row, amount) do
    spent = row["amount"] - row["remaining"]
    delta = amount - row["amount"]
    company = State.get(state, "companies", row["company_id"])

    cond do
      amount < spent ->
        {:error, :visit_budget_committed}

      delta > company["cash"] - company["reserved"] or (delta > 0 and company["unpaid"] > 0) ->
        {:error, :insufficient_cash}

      true ->
        {:ok,
         state
         |> move_cash(row["company_id"], delta, "visit_budget")
         |> State.put("visit_budgets", row["id"], %{
           row
           | "amount" => amount,
             "remaining" => row["remaining"] + delta,
             "strict" => true,
             "skip" => false
         })}
    end
  end

  def consume_visit(state, id, amount) do
    row = State.get(state, "visit_budgets", id)

    unless row && row["strict"] && not row["skip"] && amount <= row["remaining"],
      do: raise(ArgumentError, "Purchase exceeds reserved visit budget")

    State.put(state, "visit_budgets", id, %{row | "remaining" => row["remaining"] - amount})
  end

  def release_visit(state, row),
    do:
      state
      |> move_cash(row["company_id"], -row["remaining"], "visit_budget_release")
      |> State.delete("visit_budgets", row["id"])

  def request(state, spec, policy, required) do
    State.put(state, "departure_requests", spec.ship_id, %{
      "id" => spec.ship_id,
      "ship_id" => spec.ship_id,
      "company_id" => spec.company_id,
      "destination" => spec.port,
      "stop_id" => spec.stop_id,
      "visit" => spec.visit,
      "configured" => spec.configured,
      "policy" => policy,
      "required" => required,
      "blocked_ms" => state.clock_ms,
      "accumulated" => 0,
      "window_deadline_ms" => nil,
      "cooldown_ms" => nil
    })
  end

  def accumulate(state, request, amount, deadline) do
    unless amount >= 0 and request["accumulated"] + amount <= request["required"],
      do: raise(ArgumentError, "Invalid departure accumulation")

    state
    |> move_cash(request["company_id"], amount, "departure_accumulation")
    |> State.put("departure_requests", request["id"], %{
      request
      | "accumulated" => request["accumulated"] + amount,
        "window_deadline_ms" => request["window_deadline_ms"] || deadline
    })
  end

  def release_accumulation(state, request, cooldown \\ nil) do
    state
    |> move_cash(request["company_id"], -request["accumulated"], "departure_accumulation_release")
    |> State.put("departure_requests", request["id"], %{
      request
      | "accumulated" => 0,
        "window_deadline_ms" => nil,
        "cooldown_ms" => cooldown
    })
  end

  def abandon_request(state, row),
    do: state |> release_accumulation(row) |> State.delete("departure_requests", row["id"])

  def complete_request(state, id), do: State.delete(state, "departure_requests", id)

  def budget(state, ship, port) do
    State.owned(state, "visit_budgets", "company_id", ship["company_id"])
    |> Enum.find(
      &(&1["ship_id"] == ship["id"] and &1["port"] == port and current_budget?(state, ship, &1))
    )
  end

  defp current_budget?(state, ship, row) do
    route = State.get(state, "ship_routes", ship["id"])

    if route && row["stop_id"],
      do:
        Enum.any?(State.entities(state, "route_stops"), fn {_, stop} ->
          stop["id"] == row["stop_id"] and stop["position"] == route["cursor"]
        end),
      else: true
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
