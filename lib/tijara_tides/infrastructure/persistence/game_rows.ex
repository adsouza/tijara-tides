defmodule TijaraTides.Infrastructure.Persistence.GameRows do
  @moduledoc "Typed relational rows mapped to pure domain state; SQL names are a closed whitelist."
  @specs %{
    "reporting_accounts" => Enum.map(~w(id capital since_ms at_ms), &{&1, &1}),
    "financial_reports" =>
      Enum.map(
        ~w(id company_id period period_index capital_ms observed_ms revenue cargo_cost operating depreciation),
        &{&1, &1}
      ),
    "email_requests" => [
      {"attempts", "attempts"},
      {"retry_ms", "retry_ms"},
      {"id", "id"},
      {"token_hash", "token_hash"},
      {"email", "email"},
      {"purpose", "purpose"},
      {"account_id", "account_id"},
      {"requester", "requester"},
      {"created_ms", "created_ms"},
      {"expires_ms", "expires_ms"},
      {"used_session", "used_session"},
      {"delivery", "delivery"}
    ],
    "guarantees" => [
      {"id", "id"},
      {"company_id", "company_id"},
      {"sponsor_id", "sponsor_id"},
      {"beneficiary_id", "beneficiary_id"},
      {"borrower_company_id", "borrower_company_id"},
      {"amount", "amount"},
      {"forfeited", "forfeited"},
      {"status", "status"},
      {"created_ms", "created_ms"}
    ],
    "loan_installments" => [
      {"id", "id"},
      {"loan_id", "loan_id"},
      {"company_id", "company_id"},
      {"due_ms", "due_ms"},
      {"principal_due", "principal_due"},
      {"interest_due", "interest_due"}
    ],
    "operating_bills" => [
      {"id", "id"},
      {"company_id", "company_id"},
      {"due_ms", "due_ms"},
      {"remaining", "remaining"}
    ],
    "loans" => [
      {"guarantee_id", "guarantee_id"},
      {"id", "id"},
      {"company_id", "company_id"},
      {"principal", "principal"},
      {"remaining", "remaining"},
      {"principal_due", "principal_due"},
      {"interest_due", "interest_due"},
      {"interest_accrued", "interest_accrued"},
      {"interest_remainder", "interest_remainder"},
      {"interest_at_ms", "interest_at_ms"},
      {"overdue_ms", "overdue_ms"},
      {"next_due_ms", "next_due_ms"},
      {"period_ms", "period_ms"},
      {"periods_left", "periods_left"},
      {"rate_bps", "rate_bps"},
      {"installment", "installment"},
      {"status", "status"},
      {"created_ms", "created_ms"}
    ],
    "bankruptcy_events" => [
      {"id", "id"},
      {"company_id", "company_id"},
      {"account_id", "account_id"},
      {"created_ms", "created_ms"},
      {"restart_ms", "restart_ms"},
      {"reason", "reason"},
      {"guaranteed_debt", "guaranteed_debt_cents"},
      {"guarantee_id", "guarantee_id"}
    ],
    "ship_routes" =>
      Enum.map(
        ~w(id ship_id company_id status cursor visit phase auto_depart stop_after reason),
        &{&1, &1}
      ),
    "route_stops" => [
      {"id", "id"},
      {"ship_id", "ship_id"},
      {"company_id", "company_id"},
      {"position", "position"},
      {"port", "port_id"}
    ],
    "route_rules" => [
      {"id", "id"},
      {"ship_id", "ship_id"},
      {"company_id", "company_id"},
      {"stop_id", "stop_id"},
      {"side", "side"},
      {"good", "good_id"},
      {"quantity", "quantity_lots"},
      {"quantity_mode", "quantity_mode"},
      {"limit", "limit_cents"},
      {"budget", "budget_cents"}
    ],
    "visit_plans" => [
      {"id", "id"},
      {"ship_id", "ship_id"},
      {"company_id", "company_id"},
      {"port", "port_id"},
      {"onward", "onward_port_id"},
      {"auto_depart", "auto_depart"},
      {"departure_wait", "departure_wait"}
    ],
    "ship_instructions" => [
      {"id", "id"},
      {"company_id", "company_id"},
      {"ship_id", "ship_id"},
      {"port", "port_id"},
      {"good", "good_id"},
      {"side", "side"},
      {"quantity", "quantity_lots"},
      {"quantity_mode", "quantity_mode"},
      {"filled", "filled_lots"},
      {"limit", "limit_cents"},
      {"budget", "budget_cents"},
      {"spent", "spent_cents"},
      {"onward", "onward_port_id"},
      {"status", "status"},
      {"reason", "reason"},
      {"created_ms", "created_ms"}
    ],
    "accounts" => [
      {"id", "id"},
      {"company_id", "company_id"},
      {"inviter", "inviter_account_id"},
      {"bankruptcies", "bankruptcies"},
      {"suspended_ms", "suspended_ms"},
      {"email", "email"},
      {"invite_quota", "invite_quota"},
      {"created_ms", "created_ms"}
    ],
    "companies" => [
      {"id", "id"},
      {"account_id", "account_id"},
      {"name", "name"},
      {"cash", "cash_cents"},
      {"reserved", "reserved_cents"},
      {"profit", "profit_cents"},
      {"unpaid", "unpaid_cents"},
      {"created_ms", "created_ms"},
      {"last_invite_year", "last_invite_year"},
      {"unpaid_since", "unpaid_since"},
      {"arrears_since", "arrears_since"},
      {"bankruptcy_ms", "bankruptcy_ms"}
    ],
    "ships" => [
      {"id", "id"},
      {"company_id", "company_id"},
      {"name", "name"},
      {"class", "class_id"},
      {"book_value", "book_value_cents"},
      {"built_ms", "built_ms"},
      {"build_value", "build_value_cents"},
      {"port", "port_id"},
      {"status", "status"},
      {"arrive_ms", "arrive_ms"},
      {"destination", "destination_port_id"},
      {"depart_ms", "depart_ms"},
      {"fuel_total", "fuel_total_cents"},
      {"fuel_burned", "fuel_burned_cents"},
      {"crew_remainder", "crew_remainder"},
      {"last_cost_ms", "last_cost_ms"},
      {"last_liquid", "last_liquid_good_id"},
      {"voyage_speedup", "voyage_speedup"}
    ],
    "markets" => [
      {"port", "port_id"},
      {"good", "good_id"},
      {"merchant", "merchant"},
      {"seller", "seller"},
      {"buyer", "buyer"},
      {"stock", "stock_lots"},
      {"demand", "demand_lots"},
      {"budget", "budget_cents"},
      {"last_production", "last_production_ms"}
    ],
    "sessions" => [{"account_id", "account_id"}, {"expires_at", "expires_at_ms"}],
    "invitations" => [
      {"inviter", "inviter_account_id"},
      {"expires_ms", "expires_ms"},
      {"status", "status"},
      {"seed", "seed"},
      {"invitee", "invitee_account_id"}
    ],
    "notices" => [{"account_id", "account_id"}, {"text", "message"}, {"clock_ms", "clock_ms"}]
  }
  @kinds ~w(accounts companies ships markets sessions invitations notices ship_instructions visit_plans loans bankruptcy_events operating_bills loan_installments guarantees email_requests reporting_accounts financial_reports ship_routes route_stops route_rules)

  @children %{
    "ships" =>
      {"cargo", "game_ship_cargo_batches", "ship_id",
       [
         {"lot_id", "lot_id"},
         {"quantity", "quantity_lots"},
         {"expires_ms", "expires_ms"},
         {"good", "good_id"},
         {"unit_cost", "unit_cost_cents"}
       ]},
    "markets" =>
      {"batches", "game_market_stock_batches", "market_id",
       [{"lot_id", "lot_id"}, {"quantity", "quantity_lots"}, {"expires_ms", "expires_ms"}]}
  }
  @optional %{"ships" => ["voyage_speedup"], "invitations" => ["invitee"]}

  def load(repo, world, wall_ms \\ nil) do
    Map.new(@kinds, fn kind ->
      fields = @specs[kind]
      columns = ["id" | Enum.map(fields, &elem(&1, 1))]

      rows =
        repo.query!(
          "SELECT #{Enum.join(columns, ",")} FROM game_#{kind} WHERE world_id=$1" <>
            current_reports_filter(kind) <> history_filter(kind, wall_ms),
          if(wall_ms != nil and kind in ["sessions", "email_requests"],
            do: [world, wall_ms],
            else: [world]
          )
        ).rows

      entities =
        Map.new(rows, &decode_row(kind, &1))

      {kind, load_children(repo, world, kind, entities)}
    end)
    |> Map.reject(fn {_, rows} -> map_size(rows) == 0 end)
  end

  def lookup(repo, world, kind, value, field \\ "id")
      when kind in ["sessions", "invitations", "email_requests"] and
             field in ["id", "token_hash"] do
    if field == "token_hash" and kind != "email_requests",
      do: raise(ArgumentError, "Invalid history lookup")

    columns = ["id" | Enum.map(@specs[kind], &elem(&1, 1))]

    case repo.query!(
           "SELECT #{Enum.join(columns, ",")} FROM game_#{kind} WHERE world_id=$1 AND #{field}=$2",
           [world, value]
         ).rows do
      [] -> nil
      [row] -> decode_row(kind, row)
    end
  end

  defp decode_row(kind, [id | values]) do
    data =
      @specs[kind]
      |> Enum.map(&elem(&1, 0))
      |> Enum.zip(values)
      |> Map.new(fn {key, value} ->
        {key, if(key == "capital_ms", do: Decimal.to_integer(value), else: value)}
      end)

    data =
      Enum.reduce(Map.get(@optional, kind, []), data, fn key, data ->
        if is_nil(data[key]), do: Map.delete(data, key), else: data
      end)

    {id, data}
  end

  defp history_filter(_, nil), do: ""
  defp history_filter("sessions", _), do: " AND expires_at_ms > $2"
  defp history_filter("invitations", _), do: " AND status='issued'"

  defp history_filter("email_requests", _),
    do: """
     AND (created_ms > $2::bigint - 3600000 OR
       (delivery='pending' AND used_session IS NULL AND expires_ms > CASE WHEN purpose='invite'
         THEN (SELECT clock_ms FROM game_worlds WHERE id=$1) ELSE $2::bigint END) OR
       id IN (SELECT id FROM (SELECT id,row_number() OVER (PARTITION BY account_id ORDER BY created_ms DESC,id) AS n
         FROM game_email_requests WHERE world_id=$1 AND purpose IN ('link','invite')) recent WHERE n<=10))
    """

  defp history_filter(_, _), do: ""

  defp current_reports_filter("financial_reports"),
    do:
      " AND period_index=(SELECT clock_ms / CASE period WHEN 'quarter' THEN 604800000 ELSE 2419200000 END FROM game_worlds WHERE id=$1)"

  defp current_reports_filter(_), do: ""

  defp load_children(repo, world, kind, entities) do
    case @children[kind] do
      nil ->
        entities

      {key, table, parent, fields} ->
        columns = [parent | Enum.map(fields, &elem(&1, 1))]

        rows =
          repo.query!(
            "SELECT #{Enum.join(columns, ",")} FROM #{table} WHERE world_id=$1 ORDER BY #{parent},position",
            [world]
          ).rows

        children =
          Enum.group_by(rows, &hd/1, fn [_parent | values] ->
            fields |> Enum.map(&elem(&1, 0)) |> Enum.zip(values) |> Map.new()
          end)

        Map.new(entities, fn {id, data} -> {id, Map.put(data, key, Map.get(children, id, []))} end)
    end
  end

  def write(repo, world, before, after_state) do
    if Application.get_env(:tijara_tides, :audit_mutations, false),
      do: TijaraTides.Domain.ChangeSet.assert_complete!(before, after_state)

    changes = TijaraTides.Domain.ChangeSet.since(before, after_state)
    unknown = Enum.uniq(for {{kind, _}, _} <- changes, do: kind) -- @kinds
    if unknown != [], do: raise(ArgumentError, "Unsupported entity kinds: #{inspect(unknown)}")
    grouped = Enum.group_by(changes, fn {{kind, _}, _} -> kind end)

    # Rows that already exist are written first. One transaction may move a unique key
    # from an old row to a new one — a sponsor releasing an escrow while pledging the
    # next — and a partial unique index rejects the pair if the insert lands first.
    # Existing rows and new rows use separate batches, preserving that ordering.
    for kind <- @kinds, rows = Map.get(grouped, kind, []), rows != [] do
      {deletes, puts} =
        rows
        |> Enum.sort_by(fn {{_, row_id}, _} ->
          if get_in(before, [:entities, kind, row_id]) == nil, do: 1, else: 0
        end)
        |> Enum.split_with(fn {_, operation} -> operation == :delete end)

      write_batch(repo, world, kind, before, after_state, puts)
      delete_batch(repo, world, kind, before, deletes)
    end

    :ok
  end

  # Batch existing rows separately from inserts: a tick changes every moving ship,
  # and a round trip each would dominate the commit. New rows must reject collisions.
  defp write_batch(_repo, _world, _kind, _before, _after_state, []), do: :ok

  defp write_batch(repo, world, kind, before, after_state, puts) do
    # Assignments inside a comprehension act as filters, which would silently drop every
    # insert here, where `old` is nil. Keep the lookups outside one.
    pending =
      puts
      |> Enum.map(fn {{_, id}, _} ->
        data =
          get_in(after_state, [:entities, kind, id]) ||
            raise(ArgumentError, "Changed row missing before persistence")

        {id, get_in(before, [:entities, kind, id]), data}
      end)
      |> Enum.filter(fn {_, old, data} -> data != old end)

    for {id, old, data} <- pending do
      check_market_version(repo, world, kind, id, old, before)
      validate_entity!(kind, id, old, data)
    end

    fields = Enum.reject(@specs[kind], fn {_, column} -> column == "id" end)
    columns = ["world_id", "id" | Enum.map(fields, &elem(&1, 1))]

    assignments =
      Enum.map_join(fields, ",", fn {_, column} -> "#{column}=EXCLUDED.#{column}" end)

    # Bind parameters are capped per statement, so very large batches are chunked.
    pending
    |> Enum.chunk_by(fn {_, old, _} -> is_nil(old) end)
    |> Enum.flat_map(&Enum.chunk_every(&1, max(1, div(60_000, length(columns)))))
    |> Enum.each(fn chunk ->
      values =
        Enum.flat_map(chunk, fn {id, _, data} ->
          [world, id | Enum.map(fields, fn {key, _} -> column_value(key, data[key]) end)]
        end)

      placeholders =
        chunk
        |> Enum.with_index()
        |> Enum.map_join(",", fn {_, row} ->
          "(" <>
            Enum.map_join(1..length(columns), ",", fn n ->
              "$#{row * length(columns) + n}"
            end) <> ")"
        end)

      # A missing row in the caller's snapshot is an insert, never permission to
      # overwrite another writer's row (which would also bypass the market CAS).
      conflict =
        case hd(chunk) do
          {_, nil, _} -> ""
          _ -> " ON CONFLICT (world_id,id) DO UPDATE SET #{assignments}"
        end

      repo.query!(
        "INSERT INTO game_#{kind}(#{Enum.join(columns, ",")}) VALUES #{placeholders}" <>
          conflict,
        values
      )
    end)

    case @children[kind] do
      nil ->
        :ok

      {key, table, parent, child} ->
        for {id, old, data} <- pending do
          write_children(
            repo,
            world,
            id,
            table,
            parent,
            child,
            if(old, do: old[key], else: []),
            data[key]
          )
        end
    end

    :ok
  end

  defp delete_batch(_repo, _world, _kind, _before, []), do: :ok

  defp delete_batch(repo, world, kind, before, deletes) do
    ids =
      for {{_, id}, _} <- deletes, get_in(before, [:entities, kind, id]) != nil do
        check_market_version(repo, world, kind, id, get_in(before, [:entities, kind, id]), before)
        id
      end

    if ids != [],
      do: repo.query!("DELETE FROM game_#{kind} WHERE world_id=$1 AND id=ANY($2)", [world, ids])

    :ok
  end

  defp column_value("capital_ms", value), do: Decimal.new(value)
  defp column_value(_key, value), do: value

  defp validate_entity!(kind, id, _old, data) do
    keys = Enum.map(@specs[kind], &elem(&1, 0))

    keys =
      case @children[kind] do
        nil -> keys
        {key, _, _, _} -> [key | keys]
      end

    if Map.keys(data) -- keys != [], do: raise(ArgumentError, "Unsupported fields for #{kind}")
    if "id" in keys and data["id"] != id, do: raise(ArgumentError, "Entity ID mismatch")
    :ok
  end

  defp check_market_version(repo, world, "markets", id, old, before) when not is_nil(old) do
    expected = Map.get(Map.get(before, :market_versions, %{}), id, 0)

    result =
      repo.query!(
        "UPDATE game_markets SET version=version+1 WHERE world_id=$1 AND id=$2 AND version=$3",
        [world, id, expected]
      )

    if result.num_rows != 1, do: repo.rollback(:market_conflict)
  end

  defp check_market_version(_, _, _, _, _, _), do: :ok

  defp write_children(repo, world, id, _table, parent, fields, old, new) do
    if old != new do
      old_rows =
        old |> Enum.with_index() |> Map.new(fn {row, index} -> {row["lot_id"], {row, index}} end)

      for {row, index} <- Enum.with_index(new), old_rows[row["lot_id"]] != {row, index} do
        if Map.keys(row) -- Enum.map(fields, &elem(&1, 0)) != [],
          do: raise(ArgumentError, "Unsupported batch fields")

        case repo.query!(
               "SELECT good_id,expires_ms FROM game_cargo_lots WHERE world_id=$1 AND id=$2",
               [world, row["lot_id"]]
             ).rows do
          [[good, expiry]] ->
            unless expiry == row["expires_ms"] and (parent == "market_id" or good == row["good"]),
              do: raise(ArgumentError, "Lot identity does not match cargo")

          _ ->
            raise ArgumentError, "Unknown cargo lot"
        end

        ship = if parent == "ship_id", do: id
        market = if parent == "market_id", do: id

        repo.query!(
          "INSERT INTO game_cargo_holdings(world_id,lot_id,ship_id,market_id,position,quantity_lots,unit_cost_cents) VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(world_id,lot_id) DO UPDATE SET ship_id=EXCLUDED.ship_id,market_id=EXCLUDED.market_id,position=EXCLUDED.position,quantity_lots=EXCLUDED.quantity_lots,unit_cost_cents=EXCLUDED.unit_cost_cents",
          [world, row["lot_id"], ship, market, index, row["quantity"], row["unit_cost"]]
        )
      end

      repo.query!(
        "DELETE FROM game_cargo_holdings WHERE world_id=$1 AND #{parent}=$2 AND NOT (lot_id=ANY($3::text[]))",
        [world, id, Enum.map(new, & &1["lot_id"])]
      )
    end
  end
end
