defmodule TijaraTides.Domain.Visibility do
  @moduledoc "Public and owner-only disclosure policies; no client filtering is trusted for privacy."
  import TijaraTides.Domain.State, only: [get: 3, entities: 2, owned: 4]

  def public(state, catalogue) do
    # One pass over the fleet for every port, so the snapshot reads the same admission
    # model the coordinator does rather than ranking queues by its own rules.
    ports = TijaraTides.Domain.PortBerths.load_all(state, catalogue)

    %{
      "clock_ms" => state.clock_ms,
      "revision" => state.revision,
      "ports" => catalogue["ports"],
      "goods" => catalogue["goods"],
      "berths" =>
        Map.new(ports, fn {port, model} ->
          {port,
           %{
             "capacity" => model.capacity,
             "occupied" => MapSet.size(model.held),
             "queued" => length(model.waiting)
           }}
        end),
      "companies" =>
        Map.new(entities(state, "companies"), fn {id, c} ->
          {id, Map.take(c, ["id", "name", "created_ms", "bankruptcy_ms"])}
        end),
      "ships" =>
        Map.new(entities(state, "ships"), fn {id, s} ->
          {id,
           Map.take(s, [
             "id",
             "company_id",
             "name",
             "class",
             "port",
             "destination",
             "status",
             "depart_ms",
             "arrive_ms",
             "berth_queued_ms",
             "berth_granted_ms"
           ])
           |> Map.put("queue_position", queue_position(ports[s["port"]], id))}
        end)
    }
  end

  # A sailing ship's port holds no model of its own, so it ranks nowhere.
  defp queue_position(nil, _id), do: nil
  defp queue_position(model, id), do: TijaraTides.Domain.PortBerths.position(model, id)

  def private(state, account) do
    %{
      "account" => Map.drop(account, ["inviter"]),
      "email_deliveries" =>
        owned(state, "email_requests", "account_id", account["id"])
        |> Enum.filter(&(&1["purpose"] in ["link", "invite"]))
        |> Enum.sort_by(& &1["created_ms"], :desc)
        |> Enum.take(10)
        |> Enum.map(&Map.take(&1, ["email", "purpose", "delivery", "expires_ms", "used_session"]))
        |> Enum.map(fn row ->
          row |> Map.put("verified", row["used_session"] != nil) |> Map.delete("used_session")
        end),
      "finance" => TijaraTides.Domain.CompanyFinance.summary(state, account),
      "guarantees" => TijaraTides.Domain.Guarantees.view(state, account),
      "company" => get(state, "companies", account["company_id"]),
      "ships" =>
        Map.new(owned(state, "ships", "company_id", account["company_id"]), &{&1["id"], &1}),
      "ship_routes" =>
        Map.new(owned(state, "ship_routes", "company_id", account["company_id"]), &{&1["id"], &1}),
      "route_stops" =>
        Map.new(owned(state, "route_stops", "company_id", account["company_id"]), &{&1["id"], &1}),
      "route_rules" =>
        Map.new(owned(state, "route_rules", "company_id", account["company_id"]), &{&1["id"], &1}),
      "visit_plans" =>
        Map.new(owned(state, "visit_plans", "company_id", account["company_id"]), &{&1["id"], &1}),
      "ship_instructions" =>
        Map.new(
          owned(state, "ship_instructions", "company_id", account["company_id"]),
          &{&1["id"], &1}
        ),
      "notices" => Map.get(Map.get(state, :notices_by_account, %{}), account["id"], [])
    }
  end
end
