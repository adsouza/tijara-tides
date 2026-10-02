defmodule TijaraTides.SettledCheck do
  @moduledoc """
  Test-only oracle for transition-owned invariants. Commands and ticks call it
  through a compile-time seam enabled in config/test.exs; it raises when a
  transition leaves behind state that its own transition should have released.

  The rules are stated independently of the domain's release code. Clock-driven
  conditions (expiry, spoilage, decay, auction closes) are out of scope: the tick
  passes own those. Departure-request readiness is rechecked where allocation uses
  it, so only visit budgets are checked on the funding side. A budget funds exactly
  one visit: the route's current stop visit, or a planned single-port visit whose
  orders are still open.
  """
  use Boundary, deps: [TijaraTides.Domain]
  alias TijaraTides.Domain.ReadState

  def assert_settled!(before, state, catalogue, where) do
    case violations(state, catalogue) -- violations(before, catalogue) do
      [] ->
        state

      introduced ->
        raise ArgumentError,
              "#{where} left unreleased state: #{inspect(Enum.take(introduced, 10))}"
    end
  end

  def violations(state, catalogue) do
    Enum.sort(
      claims(state) ++ orders(state) ++ bids(state) ++ links(state) ++ budgets(state, catalogue)
    )
  end

  defp rows(state, kind), do: Map.values(ReadState.entities(state, kind))
  defp get(state, kind, id), do: id && ReadState.get(state, kind, id)
  defp bankrupt?(state, company), do: get(state, "companies", company)["bankruptcy_ms"] != nil

  defp claims(state) do
    for r <- rows(state, "warehouse_reservations"),
        w = get(state, "warehouses", r["warehouse_id"]),
        reason = claim_violation(state, r, w),
        do: {:claim, reason, r["id"]}
  end

  defp claim_violation(_state, _r, nil), do: :without_warehouse

  defp claim_violation(state, r, w) do
    owner = w["company_id"]
    stop = get(state, "route_stops", r["stop_id"])

    cond do
      r["auction_id"] ->
        a = get(state, "auctions", r["auction_id"])
        if !(a && a["company_id"] == owner && a["status"] == "scheduled"), do: :without_auction

      bankrupt?(state, owner) ->
        :insolvent_owner

      r["order_id"] ->
        if get(state, "exchange_orders", r["order_id"])["company_id"] != owner, do: :without_order

      r["bid_id"] ->
        if get(state, "auction_bids", r["bid_id"])["company_id"] != owner, do: :without_bid

      get(state, "ships", r["ship_id"])["company_id"] != owner ->
        :without_ship

      r["stop_id"] && !(stop && stop["ship_id"] == r["ship_id"] && stop["port"] == w["port"]) ->
        :without_stop

      true ->
        nil
    end
  end

  defp orders(state),
    do:
      for(
        o <- rows(state, "exchange_orders"),
        bankrupt?(state, o["company_id"]),
        do: {:order, :insolvent_owner, o["id"]}
      )

  defp bids(state) do
    for b <- rows(state, "auction_bids"),
        get(state, "auctions", b["auction_id"])["status"] == "scheduled",
        bankrupt?(state, b["company_id"]),
        do: {:bid, :insolvent_bidder, b["id"]}
  end

  defp links(state) do
    for l <- rows(state, "remote_links"),
        l["status"] == "active",
        is_nil(get(state, "route_rules", l["id"])) or bankrupt?(state, l["company_id"]),
        do: {:link, :without_rule, l["id"]}
  end

  defp budgets(state, _catalogue) do
    for b <- rows(state, "visit_budgets"),
        not funds_a_visit?(state, b),
        do: {:budget, :stale, b["id"]}
  end

  defp funds_a_visit?(state, b) do
    ship = get(state, "ships", b["ship_id"])

    ship != nil and ship["company_id"] == b["company_id"] and
      not bankrupt?(state, b["company_id"]) and
      if(b["stop_id"],
        do: current_stop?(state, ship, b),
        else: open_single_visit?(state, ship, b)
      )
  end

  defp current_stop?(state, ship, b) do
    route = get(state, "ship_routes", ship["id"])
    stop = get(state, "route_stops", b["stop_id"])
    at = if ship["status"] == "sailing", do: ship["destination"], else: ship["port"]

    route != nil and stop != nil and route["status"] != "draft" and
      not route["visit_finished"] and not route["wait_timed_out"] and
      b["visit"] == route["visit"] and stop["ship_id"] == ship["id"] and
      stop["position"] == route["cursor"] and stop["port"] == b["port"] and at == b["port"]
  end

  defp open_single_visit?(state, ship, b) do
    orders =
      for o <- rows(state, "ship_instructions"),
          o["ship_id"] == ship["id"] and o["port"] == b["port"],
          do: o

    get(state, "visit_plans", b["id"]) != nil and
      not (ship["status"] not in ["loading", "unloading"] and orders != [] and
             Enum.all?(orders, &(&1["status"] not in ["planned", "waiting"])))
  end
end
