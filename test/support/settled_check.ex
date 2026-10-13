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
    introduced =
      (violations(state, catalogue) -- violations(before, catalogue)) ++
        piracy_transition(before, state, where) ++ protection_requests(before, state)

    case introduced do
      [] ->
        state

      introduced ->
        raise ArgumentError,
              "#{where} left unreleased state: #{inspect(Enum.take(introduced, 10))}"
    end
  end

  def violations(state, catalogue) do
    Enum.sort(
      claims(state) ++
        orders(state) ++
        bids(state) ++
        links(state) ++
        budgets(state, catalogue) ++
        handling(state) ++
        operator_dormancy(state) ++
        piracy_indices(state) ++
        closed_loans(state) ++ lot_locations(state) ++ lot_splits(state) ++ notices(state)
    )
  end

  # game_cargo_holdings gives each lot one location (a duplicate in one upsert
  # batch also fails the statement), and validate_lot_split accepts one split per
  # parent, after which the parent is no longer held.
  defp lot_locations(state) do
    held = held_lots(state)

    for {lot, count} <- Enum.frequencies(held), count > 1, do: {:lot, :duplicate_location, lot}
  end

  defp lot_splits(state) do
    held = MapSet.new(held_lots(state))
    children = Enum.group_by(Map.get(state, :new_lots, []), & &1["parent_lot_id"])

    for {parent, lots} <- children,
        parent != nil,
        reason = split_violation(lots, parent, held),
        do: {:lot, reason, parent}
  end

  defp split_violation(lots, _parent, _held) when length(lots) > 2, do: :split_twice
  defp split_violation(_lots, parent, held), do: if(parent in held, do: :split_parent_held)

  defp held_lots(state) do
    for {kind, field} <- [{"ships", "cargo"}, {"warehouses", "cargo"}, {"markets", "batches"}],
        row <- rows(state, kind),
        batch <- row[field] || [],
        batch["lot_id"] != nil,
        do: batch["lot_id"]
  end

  # game_notices.arguments is jsonb, which refuses U+0000 and anything Jason
  # cannot encode.
  defp notices(state) do
    for {id, row} <- ReadState.entities(state, "notices"),
        payload = Map.take(row, ["arguments", "text"]),
        not match?({:ok, json} when is_binary(json), Jason.encode(payload)) or
          Jason.encode!(payload) =~ "\\u0000",
        do: {:notice, :unstorable, id}
  end

  # Mirrors game_loans_check2 and check5: a loan leaves "open" only after its
  # principal and every cent of due or accruing interest has been settled.
  defp closed_loans(state) do
    for loan <- rows(state, "loans"),
        loan["status"] != "open",
        loan["remaining"] + loan["principal_due"] + loan["interest_due"] +
          loan["interest_accrued"] > 0,
        do: {:loan, :closed_with_balance, loan["id"]}
  end

  defp protection_requests(before, state) do
    for row <- rows(state, "departure_requests"),
        old = get(before, "departure_requests", row["id"]),
        old != nil && old["protection"] != row["protection"],
        do: {:piracy, :request_protection_changed, row["id"]}
  end

  defp rows(state, kind), do: Map.values(ReadState.entities(state, kind))

  defp piracy_indices(state) do
    for ship <- rows(state, "ships"),
        records = get_in(ship, ["piracy", "resolved"]) || [],
        indices = Enum.map(records, & &1["index"]),
        length(indices) != length(Enum.uniq(indices)),
        do: {:piracy, :duplicate_crossing, ship["id"]}
  end

  defp piracy_transition(before, state, where) do
    events = Enum.drop(Map.get(state, :journal, []), length(Map.get(before, :journal, [])))

    Enum.flat_map(rows(state, "ships"), fn ship ->
      old = get(before, "ships", ship["id"]) || %{}
      prior = get_in(old, ["piracy", "incidents"]) || []
      added = (get_in(ship, ["piracy", "incidents"]) || []) -- prior

      # Arrival clears the voyage, and automation can start another in this tick.
      # Its notices retain the amounts, including replacements of older voyages' keys.
      added =
        if is_nil(ship["piracy"]) or
             (old["status"] == "sailing" and ship["port"] == old["destination"]) do
          for {id, notice} <- ReadState.entities(state, "notices"),
              notice["code"] == "ship.piracy",
              String.starts_with?(id, "piracy:" <> ship["id"] <> ":"),
              get(before, "notices", id) != notice,
              do: notice["arguments"]
        else
          added
        end

      postings =
        for event <- events,
            event.ship == ship["id"],
            entries = Enum.filter(event.entries, &(elem(&1, 0) == "piracy_charge_expense")),
            entries != [],
            do: entries

      expected =
        Enum.frequencies(
          for i <- added,
              i["charge"] > 0,
              do:
                Enum.reject(
                  [
                    {"piracy_charge_expense", i["charge"]},
                    {"piracy_charge_expense", -i["recovery"]}
                  ],
                  &(elem(&1, 1) == 0)
                )
        )

      actual = Enum.frequencies(postings)

      money =
        if expected != actual,
          do: [{:piracy, :incident_posting, ship["id"]}],
          else: []

      hold =
        Enum.find(
          get_in(old, ["weather", "holds"]) || [],
          &(&1["source"] == "piracy" and &1["starts_ms"] <= before.clock_ms and
              before.clock_ms < &1["until_ms"])
        )

      changed = Enum.any?(~w(destination voyage_path depart_ms), &(old[&1] != ship[&1]))

      motion =
        if (where != "tick" and hold) && changed,
          do: [{:piracy, :held_diversion, ship["id"]}],
          else: []

      protection = ship["piracy"]
      new_voyage = changed && protection && ship["status"] == "sailing"

      protected =
        if new_voyage do
          terms =
            TijaraTides.Domain.Piracy.crossing_quotes(
              protection["pending"],
              ship,
              ship["depart_ms"],
              ship["weather"],
              protection["model"]
            )[protection["protection"]]

          entries =
            for e <- events,
                e.ship == ship["id"] and e.kind in ["departure", "reroute"],
                entry <- e.entries,
                elem(entry, 0) in ["piracy_guard_expense", "piracy_premium_expense"],
                do: entry

          expected =
            Enum.reject(
              [
                {"piracy_guard_expense", terms["guard_fee"]},
                {"piracy_premium_expense", terms["premium"]}
              ],
              &(elem(&1, 1) == 0)
            )

          # Legacy voyages have no purchased protection. Otherwise diversion cannot change it.
          retained =
            old["status"] != "sailing" || is_nil(old["piracy"]) ||
              old["piracy"]["protection"] == protection["protection"]

          if Enum.sort(entries) == Enum.sort(expected) && retained,
            do: [],
            else: [{:piracy, :protection_posting, ship["id"]}]
        else
          []
        end

      money ++ motion ++ protected
    end) ++
      for event <- events,
          Enum.any?(event.entries, &(elem(&1, 0) == "piracy_charge_expense")) and
            is_nil(get(state, "ships", event.ship)),
          do: {:piracy, :incident_posting, event.ship}
  end

  defp operator_dormancy(state) do
    warnings =
      for row <- rows(state, "company_dormancy"),
          get(state, "accounts", row["account_id"])["operator"],
          row["closed_ms"] == nil,
          row["warned_ms"] != nil or row["closes_ms"] != nil,
          do: {:dormancy, :operator_warning, row["id"]}

    notices =
      for row <- rows(state, "notices"),
          get(state, "accounts", row["account_id"])["operator"],
          row["code"] == "company.dormancy_warning",
          do: {:dormancy, :operator_notice, row["id"]}

    emails =
      for row <- rows(state, "email_requests"),
          get(state, "accounts", row["account_id"])["operator"],
          row["purpose"] == "dormancy" and row["delivery"] == "pending",
          do: {:dormancy, :operator_email, row["id"]}

    warnings ++ notices ++ emails
  end

  defp handling(state) do
    for ship <- rows(state, "ships"),
        ship["status"] not in ["loading", "unloading"],
        ship["handling_started_ms"] != nil or ship["handling_volume_l"] != nil,
        do: {:handling, :without_operation, ship["id"]}
  end

  defp get(state, kind, id), do: id && ReadState.get(state, kind, id)
  defp bankrupt?(state, company), do: get(state, "companies", company)["bankruptcy_ms"] != nil

  defp claims(state) do
    for r <- rows(state, "warehouse_reservations"),
        reason = claim_violation(state, r, get(state, "warehouses", r["warehouse_id"])),
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
