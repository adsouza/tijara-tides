defmodule TijaraTides.Domain.Visibility do
  @moduledoc "Public and owner-only disclosure policies; no client filtering is trusted for privacy."
  import TijaraTides.Domain.State, only: [get: 3, entities: 2]

  def public(state, catalogue) do
    %{
      "clock_ms" => state.clock_ms,
      "revision" => state.revision,
      "ports" => catalogue["ports"],
      "goods" => catalogue["goods"],
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
             "arrive_ms"
           ])}
        end)
    }
  end

  def private(state, account) do
    %{
      "account" => Map.drop(account, ["inviter"]),
      "email_deliveries" =>
        entities(state, "email_requests")
        |> Map.values()
        |> Enum.filter(
          &(&1["account_id"] == account["id"] and &1["purpose"] in ["link", "invite"])
        )
        |> Enum.sort_by(& &1["created_ms"], :desc)
        |> Enum.take(10)
        |> Enum.map(&Map.take(&1, ["email", "purpose", "delivery", "expires_ms", "used_session"]))
        |> Enum.map(fn row ->
          row |> Map.put("verified", row["used_session"] != nil) |> Map.delete("used_session")
        end),
      "finance" => TijaraTides.Domain.Finance.summary(state, account),
      "guarantees" => TijaraTides.Domain.Guarantees.view(state, account),
      "company" => get(state, "companies", account["company_id"]),
      "ships" =>
        Map.filter(entities(state, "ships"), fn {_, s} ->
          s["company_id"] == account["company_id"]
        end),
      "visit_plans" =>
        Map.filter(entities(state, "visit_plans"), fn {_, plan} ->
          plan["company_id"] == account["company_id"]
        end),
      "ship_instructions" =>
        Map.filter(entities(state, "ship_instructions"), fn {_, order} ->
          order["company_id"] == account["company_id"]
        end),
      "notices" => Map.get(Map.get(state, :notices_by_account, %{}), account["id"], [])
    }
  end
end
