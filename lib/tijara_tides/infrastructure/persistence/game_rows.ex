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
      {"reason", "reason"}
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

  def load(repo, world) do
    Map.new(@kinds, fn kind ->
      fields = @specs[kind]
      columns = ["id" | Enum.map(fields, &elem(&1, 1))]

      rows =
        repo.query!(
          "SELECT #{Enum.join(columns, ",")} FROM game_#{kind} WHERE world_id=$1" <>
            current_reports_filter(kind),
          [
            world
          ]
        ).rows

      entities =
        Map.new(rows, fn [id | values] ->
          data =
            fields
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
        end)

      {kind, load_children(repo, world, kind, entities)}
    end)
    |> Map.reject(fn {_, rows} -> map_size(rows) == 0 end)
  end

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
    changes = TijaraTides.Domain.ChangeSet.since(before, after_state)
    unknown = Enum.uniq(for {{kind, _}, _} <- changes, do: kind) -- @kinds
    if unknown != [], do: raise(ArgumentError, "Unsupported entity kinds: #{inspect(unknown)}")
    grouped = Enum.group_by(changes, fn {{kind, _}, _} -> kind end)

    for kind <- @kinds, {{_, id}, operation} <- Map.get(grouped, kind, []) do
      old = get_in(before, [:entities, kind, id])

      case operation do
        :put ->
          data =
            get_in(after_state, [:entities, kind, id]) ||
              raise(ArgumentError, "Changed row missing before persistence")

          if data != old, do: write_entity(repo, world, kind, id, old, data)

        :delete ->
          if old != nil,
            do: repo.query!("DELETE FROM game_#{kind} WHERE world_id=$1 AND id=$2", [world, id])
      end
    end
  end

  defp write_entity(repo, world, kind, id, old, data) do
    fields = @specs[kind]
    keys = Enum.map(fields, &elem(&1, 0))

    keys =
      case @children[kind] do
        nil -> keys
        {key, _, _, _} -> [key | keys]
      end

    if Map.keys(data) -- keys != [], do: raise(ArgumentError, "Unsupported fields for #{kind}")
    if "id" in keys and data["id"] != id, do: raise(ArgumentError, "Entity ID mismatch")
    # Primary keys never change; an update sets only columns changed by this action.
    fields = Enum.reject(fields, fn {_, column} -> column == "id" end)

    if is_nil(old) do
      columns = ["world_id", "id" | Enum.map(fields, &elem(&1, 1))]

      values = [
        world,
        id
        | Enum.map(fields, fn {key, _} ->
            if(key == "capital_ms", do: Decimal.new(data[key]), else: data[key])
          end)
      ]

      repo.query!(
        "INSERT INTO game_#{kind}(#{Enum.join(columns, ",")}) VALUES (#{params(length(values))})",
        values
      )
    else
      changed = Enum.filter(fields, fn {key, _} -> old[key] != data[key] end)

      if changed != [] do
        assignments =
          changed
          |> Enum.with_index(3)
          |> Enum.map_join(",", fn {{_, column}, index} -> "#{column}=$#{index}" end)

        repo.query!("UPDATE game_#{kind} SET #{assignments} WHERE world_id=$1 AND id=$2", [
          world,
          id
          | Enum.map(changed, fn {key, _} ->
              if(key == "capital_ms", do: Decimal.new(data[key]), else: data[key])
            end)
        ])
      end
    end

    case @children[kind] do
      nil ->
        :ok

      {key, table, parent, fields} ->
        write_children(
          repo,
          world,
          id,
          table,
          parent,
          fields,
          if(old, do: old[key], else: []),
          data[key]
        )
    end
  end

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

  defp params(count), do: Enum.map_join(1..count, ",", &"$#{&1}")
end
