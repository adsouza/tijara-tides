defmodule TijaraTides.Domain.WarehouseWorld do
  alias TijaraTides.Domain.CompanyFinanceWorld
  alias TijaraTides.Domain.PortBerthsWorld
  alias TijaraTides.Domain.Ship.CargoRows
  alias TijaraTides.Domain.ShipWorld

  @moduledoc "Finite port storage leases with typed cargo, prepaid rent and preserved lot identity."
  import TijaraTides.Domain.State
  alias TijaraTides.Domain.{CargoRules}
  alias TijaraTides.Domain.Warehouse.Claim
  @day 86_400_000
  @terms [1, 3, 7]
  @storage_classes ["dry", "reefer", "liquid"]
  @max_lots CargoRules.max_lots()
  alias TijaraTides.Domain.Warehouse
  alias TijaraTides.Domain.Warehouse.{Rows, ReservationRows, Transition}
  alias TijaraTides.Domain.CargoLots.Scope, as: Lots

  defp load(state, row) do
    w = Rows.decode(row)
    %{w | reservations: reservations(state, w)}
  end

  defdelegate snapshot(row), to: Rows, as: :decode

  def fetch(state, id) do
    case get(state, "warehouses", id) do
      nil -> nil
      row -> load(state, row)
    end
  end

  defp save(state, w), do: put(state, "warehouses", w.id, Rows.encode(w))
  defdelegate block_litres(), to: Warehouse
  defdelegate terms(), to: Warehouse
  defdelegate pool(storage), to: Warehouse

  def pools(state) do
    entities(state, "warehouses")
    |> Map.values()
    |> Enum.group_by(&{&1["port"], &1["storage"]})
    |> Map.new(fn {{port, storage}, rows} ->
      {port <> "|" <> storage, Enum.sum(Enum.map(rows, & &1["blocks"]))}
    end)
  end

  @doc "Blocks leased in one pool, without building the world-wide utilization map."
  def used(state, port, storage) do
    Enum.sum(
      for {_, row} <- entities(state, "warehouses"),
          row["port"] == port and row["storage"] == storage,
          do: row["blocks"]
    )
  end

  defdelegate quote(used, storage, blocks, days), to: Warehouse

  def lease(state, account, cmd, id, catalogue) do
    company = get(state, "companies", account["company_id"])
    storage = cmd["storage"]

    well_formed =
      storage in @storage_classes and is_integer(cmd["blocks"]) and cmd["blocks"] > 0 and
        cmd["days"] in @terms

    price =
      if well_formed,
        do: quote(used(state, cmd["port"], storage), storage, cmd["blocks"], cmd["days"])

    cond do
      is_nil(company) or company["bankruptcy_ms"] != nil ->
        {:error, :finance_no_company}

      not well_formed or is_nil(catalogue["ports"][cmd["port"]]) ->
        {:error, :warehouse_invalid}

      storage == "liquid" and get_in(catalogue, ["goods", cmd["good"], "hold"]) != "liquid" ->
        {:error, :incompatible_cargo}

      is_nil(price) ->
        {:error, :warehouse_capacity}

      price != cmd["price"] ->
        {:error, :price_changed}

      company["cash"] - company["reserved"] < price or company["unpaid"] > 0 ->
        {:error, :insufficient_cash}

      get(state, "warehouses", id) != nil ->
        {:error, :warehouse_invalid}

      true ->
        w = %Warehouse{
          id: id,
          display_number:
            entities(state, "warehouses")
            |> Map.values()
            |> Enum.filter(&(&1["company_id"] == company["id"]))
            |> Enum.map(&(&1["display_number"] || 1))
            |> Enum.max(fn -> 0 end)
            |> Kernel.+(1),
          company_id: company["id"],
          port: cmd["port"],
          storage: storage,
          good: if(storage == "liquid", do: cmd["good"]),
          blocks: cmd["blocks"],
          started_ms: state.clock_ms,
          expires_ms: state.clock_ms + cmd["days"] * @day,
          rent: price,
          prepaid: price,
          protected_ms: state.clock_ms
        }

        state =
          save(state, w)
          |> CompanyFinanceWorld.post(company["id"], "warehouse_lease", [
            {"prepaid_rent", price},
            {"cash_available", -price}
          ])

        {:ok, state, %{}}
    end
  end

  defdelegate volume(w, catalogue), to: Warehouse
  defdelegate compatible?(w, item), to: Warehouse

  def release(state, account, id, blocks, catalogue) do
    with %{"company_id" => owner} = row <- get(state, "warehouses", id),
         true <- owner == account["company_id"],
         true <- is_integer(blocks) and blocks > 0 and blocks <= row["blocks"] do
      company = get(state, "companies", owner)
      w = load(state, row)

      cond do
        is_nil(company) or company["bankruptcy_ms"] != nil ->
          {:error, :finance_no_company}

        company["unpaid"] > 0 ->
          {:error, :insufficient_cash}

        not Warehouse.releasable?(w, blocks, state.clock_ms, catalogue) ->
          {:error, :warehouse_occupied}

        true ->
          {state, w} = accrue(state, w)

          {next, %{forfeited: forfeited, refund: refund}} =
            Warehouse.release_blocks(w, blocks, state.clock_ms, catalogue)

          state =
            CompanyFinanceWorld.post(state, owner, "warehouse_release", [
              {"prepaid_rent", -forfeited},
              {"cash_available", refund},
              {"rent_expense", forfeited - refund}
            ])

          state =
            if blocks == w.blocks,
              do: state |> clear_reservations(w) |> delete("warehouses", id),
              else: save(state, next)

          {:ok, state, %{"refund" => refund}}
      end
    else
      _ -> {:error, :warehouse_invalid}
    end
  end

  def transfer(state, account, cmd, catalogue) do
    with %{"company_id" => owner} = row <- get(state, "warehouses", cmd["warehouse"]),
         true <- owner == account["company_id"],
         %{"company_id" => ^owner, "status" => "docked"} = ship <-
           get(state, "ships", cmd["ship"]),
         true <- ship["port"] == row["port"],
         %{} = item <- catalogue["goods"][cmd["good"]],
         n when is_integer(n) and n > 0 and n <= @max_lots <- cmd["quantity"],
         side when side in ["store", "collect"] <- cmd["side"] do
      w = load(state, row)
      company = get(state, "companies", owner)

      cleaning = if side == "collect", do: cleaning_cost(ship, item), else: 0

      fee =
        cleaning +
          n * TijaraTides.Domain.PortCargoMarket.handling_rate(catalogue["ports"][w.port])

      # Collection offers only unspoiled lots, so take/4 must walk that same list: given the
      # whole manifest it matches on good alone and drains expired batches the count excluded.
      {fresh, _stale} =
        Enum.split_with(w.cargo, &(is_nil(&1.expires_ms) or &1.expires_ms > state.clock_ms))

      available =
        if side == "store",
          do: ShipWorld.cargo_available(state, ship["id"], item["id"]),
          else:
            max(
              0,
              Enum.sum(for b <- fresh, b.good == item["id"], do: b.quantity) -
                reserved_quantity(state, w, "stock", item["id"], ship["id"])
            )

      cond do
        company["bankruptcy_ms"] != nil ->
          {:error, :finance_no_company}

        state.clock_ms < w.protected_ms ->
          {:error, :warehouse_handling}

        state.clock_ms >= max(w.expires_ms, w.protected_ms) + div(@day, 2) ->
          {:error, :warehouse_expired}

        side == "store" and state.clock_ms >= w.expires_ms ->
          {:error, :warehouse_expired}

        not compatible?(w, item) or not CargoRules.compatible_cargo?(ship, item) ->
          {:error, :incompatible_cargo}

        available < n ->
          {:error, :insufficient_cargo}

        side == "store" and
            volume(w, catalogue) + reserved_volume(state, w, catalogue, ship["id"], item["id"]) +
              n * item["volume_l"] > w.blocks * block_litres() ->
          {:error, :warehouse_capacity}

        side == "collect" and not fits?(ship, item, n, catalogue) ->
          {:error, :capacity_exceeded}

        company["cash"] - company["reserved"] < fee or company["unpaid"] > 0 ->
          {:error, :insufficient_cash}

        not PortBerthsWorld.available?(state, ship, catalogue) ->
          {:error, :warehouse_berth_busy}

        true ->
          state =
            consume_reservations(
              state,
              w,
              ship["id"],
              item["id"],
              if(side == "store", do: "capacity", else: "stock"),
              n
            )

          {state, w} =
            if side == "store" do
              {s, cargo} = ShipWorld.unload_cargo(state, ship["id"], item["id"], n)
              {s, Warehouse.receive_cargo(w, Enum.map(cargo, &CargoRows.coerce/1))}
            else
              {lots, next, cargo} = Warehouse.release_cargo(lots(state), w, item["id"], n)
              s = record_lots(state, lots)

              {ShipWorld.load_cargo(
                 s,
                 ship["id"],
                 Enum.map(cargo, &CargoRows.encode/1),
                 cleaning,
                 catalogue
               ), next}
            end

          w = Warehouse.protect_handling(w, get(state, "ships", ship["id"])["arrive_ms"])

          state =
            save(state, w)
            |> ShipWorld.admit_handling(ship["id"])
            |> CompanyFinanceWorld.post(
              owner,
              "warehouse_transfer",
              [{"handling_expense", fee}, {"cash_available", -fee}],
              %{ship: ship["id"], good: item["id"]}
            )

          {:ok, state, %{}}
      end
    else
      _ -> {:error, :warehouse_invalid}
    end
  end

  def cleaning_cost(ship, item), do: Warehouse.cleaning_cost(ship["last_liquid"], item)

  defp fits?(ship, item, n, catalogue) do
    used = TijaraTides.Domain.Fleet.capacity(ship, catalogue)
    class = TijaraTides.Domain.Fleet.classes()[ship["class"]]

    used.weight + n * item["weight_kg"] <= class["weight"] and
      used.volume + n * item["volume_l"] <= class["volume"]
  end

  defp accrue(state, w) do
    {w, amount} = Warehouse.accrue(w, state.clock_ms)

    {CompanyFinanceWorld.post(state, w.company_id, "warehouse_rent", [
       {"prepaid_rent", -amount},
       {"rent_expense", amount}
     ]), w}
  end

  def advance(state, catalogue) do
    Enum.reduce(entities(state, "warehouses"), state, fn {_, row}, state ->
      {state, w} = roll_term(state, load(state, row))
      {state, w} = accrue(state, w)
      {state, w} = prepare_renewal(state, w)
      state = prune_reservations(state, w, catalogue)

      state =
        if row["prepaid"] > 0 and w.prepaid == 0 and w.next_days == nil do
          TijaraTides.Domain.Notices.notice(
            state,
            get(state, "companies", w.company_id)["account_id"],
            "warehouse:" <> w.id,
            {"warehouse.expired", %{"port" => w.port}}
          )
        else
          state
        end

      {w, lost} = Warehouse.spoil(w, state.clock_ms)

      state =
        if lost > 0,
          do:
            CompanyFinanceWorld.post(state, w.company_id, "warehouse_spoilage", [
              {"inventory", -lost},
              {"spoilage_expense", lost}
            ]),
          else: state

      bankrupt = get(state, "companies", w.company_id)["bankruptcy_ms"] != nil

      if settlement = Warehouse.clearance(w, state.clock_ms, bankrupt, catalogue) do
        %{cost: cost, value: value, charges: charges} = settlement

        state
        |> TijaraTides.Domain.Notices.notice(
          get(state, "companies", w.company_id)["account_id"],
          "warehouse:" <> w.id,
          {"warehouse.cleared", %{"port" => w.port, "refund" => value - charges}}
        )
        |> clear_reservations(w)
        |> delete("warehouses", w.id)
        |> CompanyFinanceWorld.post(w.company_id, "warehouse_clearance", [
          {"inventory", -cost},
          {"cost_of_goods", cost},
          {"sales_revenue", -value},
          {"cash_available", value - charges},
          {"rent_expense", charges + w.prepaid + w.next_rent},
          {"prepaid_rent", -w.prepaid - w.next_rent}
        ])
      else
        save(state, w)
      end
    end)
  end

  alias TijaraTides.Domain.Warehouse.Reservation

  def reservations(state, w) when is_map(state),
    do: reservations(owned(state, "warehouse_reservations", "company_id", w.company_id), w)

  def reservations(rows, w) when is_list(rows) do
    rows
    |> Enum.filter(&(&1["warehouse_id"] == w.id))
    |> Enum.map(&ReservationRows.decode/1)
    |> Enum.sort_by(&{&1.created_ms, &1.id})
  end

  def reserved_volume(state, w, catalogue, ship_id \\ nil, good \\ nil),
    do:
      Warehouse.reserved_volume(
        %{w | reservations: reservations(state, w)},
        catalogue,
        ship_id,
        good
      )

  def reserved_quantity(state, w, kind, good, except_ship \\ nil),
    do:
      Warehouse.reserved_quantity(
        %{w | reservations: reservations(state, w)},
        kind,
        good,
        except_ship
      )

  @doc "Choose this ship's earmarked stock first, then other available owned stock."
  def collection_source(state, ship, good) do
    owned(state, "warehouses", "company_id", ship["company_id"])
    |> Enum.filter(&(&1["port"] == ship["port"]))
    |> Enum.map(&load(state, &1))
    |> Enum.filter(fn w ->
      state.clock_ms < max(w.expires_ms, w.protected_ms) + div(@day, 2) and
        Enum.sum(
          for b <- w.cargo,
              b.good == good and (is_nil(b.expires_ms) or b.expires_ms > state.clock_ms),
              do: b.quantity
        ) > reserved_quantity(state, w, "stock", good, ship["id"])
    end)
    |> Enum.sort_by(fn w ->
      own =
        Enum.any?(
          reservations(state, w),
          &(&1.kind == "stock" and &1.good == good and &1.ship_id == ship["id"])
        )

      expiry =
        w.cargo
        |> Enum.filter(
          &(&1.good == good and (is_nil(&1.expires_ms) or &1.expires_ms > state.clock_ms))
        )
        |> Enum.map(&(&1.expires_ms || 9_223_372_036_854_775_807))
        |> Enum.min()

      {if(own, do: 0, else: 1), expiry, w.id}
    end)
    |> List.first()
  end

  def reserve(state, account, cmd, id, catalogue) do
    with %{"company_id" => owner} = row <- get(state, "warehouses", cmd["warehouse"]),
         true <- owner == account["company_id"],
         %{"company_id" => ^owner} = ship <- get(state, "ships", cmd["ship"]),
         %{} = item <- catalogue["goods"][cmd["good"]],
         n when is_integer(n) and n > 0 and n <= @max_lots <- cmd["quantity"],
         kind when kind in ["stock", "capacity"] <- cmd["kind"] do
      w = load(state, row)

      stop_id = if cmd["stop_id"] not in [nil, ""], do: cmd["stop_id"]
      stop = stop_id && get(state, "route_stops", stop_id)

      cond do
        get(state, "companies", owner)["bankruptcy_ms"] != nil ->
          {:error, :finance_no_company}

        state.clock_ms >= w.expires_ms ->
          {:error, :warehouse_expired}

        state.clock_ms < w.protected_ms ->
          {:error, :warehouse_handling}

        not compatible?(w, item) or not CargoRules.compatible_class?(ship, item) ->
          {:error, :incompatible_cargo}

        stop_id != nil and
            (is_nil(stop) or stop["ship_id"] != ship["id"] or stop["port"] != w.port) ->
          {:error, :warehouse_invalid}

        get(state, "warehouse_reservations", id) != nil ->
          {:error, :warehouse_invalid}

        true ->
          r = %Reservation{
            id: id,
            warehouse_id: w.id,
            company_id: owner,
            ship_id: ship["id"],
            good: item["id"],
            kind: kind,
            quantity: n,
            created_ms: state.clock_ms,
            stop_id: stop_id
          }

          case Warehouse.reserve(w, r, state.clock_ms, catalogue) do
            {:ok, transition} -> {:ok, apply_transition(state, transition), %{}}
            error -> error
          end
      end
    else
      _ -> {:error, :warehouse_invalid}
    end
  end

  def cancel_reservation(state, account, id) do
    case get(state, "warehouse_reservations", id) do
      %{"company_id" => owner} = r ->
        if owner != account["company_id"] or r["order_id"] != nil or r["auction_id"] != nil or
             r["bid_id"] != nil,
           do: {:error, :warehouse_invalid},
           else: {:ok, delete(state, "warehouse_reservations", id), %{}}

      _ ->
        {:error, :warehouse_invalid}
    end
  end

  defp consume_reservations(state, w, ship_id, good, kind, quantity),
    do: apply_transition(state, Warehouse.consume_reservations(w, ship_id, good, kind, quantity))

  defp clear_reservations(state, w),
    do:
      apply_transition(
        state,
        Warehouse.clear_reservations(%{w | reservations: reservations(state, w)})
      )

  # Also called after commands so sold ships and removed stops never leave dangling claims.
  def reconcile_reservations(state, catalogue, company_id) do
    Enum.reduce(owned(state, "warehouses", "company_id", company_id), state, fn row, s ->
      prune_reservations(s, load(state, row), catalogue)
    end)
  end

  defp prune_reservations(state, w, _catalogue) do
    valid_ids =
      Enum.reduce(reservations(state, w), MapSet.new(), fn r, ids ->
        s = state
        ship = get(s, "ships", r.ship_id)
        stop = r.stop_id && get(s, "route_stops", r.stop_id)

        order = r.order_id && get(s, "exchange_orders", r.order_id)

        owner_valid =
          cond do
            r.order_id ->
              order && order["company_id"] == w.company_id

            r.auction_id ->
              a = get(s, "auctions", r.auction_id)
              a && a["status"] == "scheduled" && a["company_id"] == w.company_id

            r.bid_id ->
              b = get(s, "auction_bids", r.bid_id)
              b && b["company_id"] == w.company_id

            true ->
              ship && ship["company_id"] == w.company_id
          end

        valid =
          owner_valid &&
            (is_nil(r.stop_id) or (stop && stop["ship_id"] == r.ship_id && stop["port"] == w.port)) &&
            (r.kind == "stock" or state.clock_ms < w.expires_ms) &&
            get(s, "companies", w.company_id)["bankruptcy_ms"] == nil

        if valid, do: MapSet.put(ids, r.id), else: ids
      end)

    transition =
      Warehouse.prune_reservations(
        %{w | reservations: reservations(state, w)},
        state.clock_ms,
        valid_ids
      )

    next = apply_transition(state, transition)

    Enum.reduce(Enum.map(transition.put, & &1.id) ++ transition.delete, next, fn id, s ->
      TijaraTides.Domain.Notices.notice(
        s,
        get(s, "companies", w.company_id)["account_id"],
        "reservation:" <> id,
        {"warehouse.reservation_released", %{"port" => w.port}}
      )
    end)
  end

  defdelegate renewal_window_ms(), to: Warehouse
  defdelegate renewal_open?(w, now), to: Warehouse

  defp lock_quote(state, w),
    do: Warehouse.lock_quote(w, state.clock_ms, used(state, w.port, w.storage))

  def renew(state, account, cmd, early \\ false) do
    with %{"company_id" => owner} = row <- get(state, "warehouses", cmd["warehouse"]),
         true <- owner == account["company_id"],
         days when days in @terms <- cmd["days"] do
      w = lock_quote(state, load(state, row))

      w =
        if early,
          do: %{w | renewal_rate: Warehouse.extension_rate(w, used(state, w.port, w.storage))},
          else: w

      company = get(state, "companies", owner)
      price = w.renewal_rate && w.renewal_rate * days

      cond do
        company["bankruptcy_ms"] != nil ->
          {:error, :finance_no_company}

        early and not Warehouse.extension_open?(w, state.clock_ms) ->
          {:error, :warehouse_extension_closed}

        not early and not renewal_open?(w, state.clock_ms) ->
          {:error, :warehouse_renewal_closed}

        price != cmd["price"] ->
          {:error, :price_changed}

        company["unpaid"] > 0 or company["cash"] - company["reserved"] < price ->
          {:error, :insufficient_cash}

        true ->
          {state, w} = pay_renewal(state, w, days, early)
          {:ok, save(state, w), %{}}
      end
    else
      _ -> {:error, :warehouse_invalid}
    end
  end

  def renewal_settings(state, account, cmd) do
    with %{"company_id" => owner} = row <- get(state, "warehouses", cmd["warehouse"]),
         true <- owner == account["company_id"],
         true <-
           cmd["days"] == 0 or
             (cmd["days"] in @terms and is_integer(cmd["price"]) and cmd["price"] >= 0) do
      w = load(state, row)

      w = Warehouse.renewal_settings(w, cmd["days"], cmd["price"])

      {state, w} = prepare_renewal(state, w)
      {:ok, save(state, w), %{}}
    else
      _ -> {:error, :warehouse_invalid}
    end
  end

  defp pay_renewal(state, w, days, early \\ false) do
    price = w.renewal_rate * days

    state =
      CompanyFinanceWorld.post(state, w.company_id, "warehouse_renewal", [
        {"prepaid_rent", price},
        {"cash_available", -price}
      ])

    {state, Warehouse.pay_renewal(w, days, state.clock_ms, early)}
  end

  defp prepare_renewal(state, w) do
    locked = lock_quote(state, w)

    state =
      if is_nil(w.renewal_rate) and locked.renewal_rate != nil,
        do:
          TijaraTides.Domain.Notices.notice(
            state,
            get(state, "companies", w.company_id)["account_id"],
            "warehouse:" <> w.id,
            {"warehouse.renewal_open", %{"port" => w.port}}
          ),
        else: state

    company = get(state, "companies", w.company_id)

    if renewal_open?(locked, state.clock_ms) and locked.auto_days != nil and
         locked.renewal_rate <= locked.auto_cap and company["bankruptcy_ms"] == nil and
         company["unpaid"] == 0 and
         company["cash"] - company["reserved"] >= locked.renewal_rate * locked.auto_days do
      pay_renewal(state, locked, locked.auto_days)
    else
      {state, locked}
    end
  end

  defp roll_term(state, w) do
    {next, amount} =
      Warehouse.roll_term(
        w,
        state.clock_ms,
        get(state, "companies", w.company_id)["bankruptcy_ms"] != nil
      )

    state =
      if next != w,
        do:
          CompanyFinanceWorld.post(state, w.company_id, "warehouse_rent", [
            {"prepaid_rent", -amount},
            {"rent_expense", amount}
          ]),
        else: state

    {state, next}
  end

  def back_order(state, %Claim{} = order, catalogue) do
    case Warehouse.back_order(fetch(state, order.warehouse_id), order, state.clock_ms, catalogue) do
      {:ok, transition} -> {:ok, apply_transition(state, transition)}
      error -> error
    end
  end

  def release_trade(state, %Claim{} = order),
    do: delete(state, "warehouse_reservations", Claim.reservation_id(order))

  def order_backed?(state, %Claim{} = order) do
    case fetch(state, order.warehouse_id) do
      nil -> false
      w -> Warehouse.order_backed?(w, order, state.clock_ms)
    end
  end

  def exchange_ready?(state, %Claim{} = order) do
    row = get(state, "warehouses", order.warehouse_id)
    order_backed?(state, order) && row["protected_ms"] <= state.clock_ms
  end

  def exchange_out(state, %Claim{} = order, n) do
    w = fetch(state, order.warehouse_id)
    transition = Warehouse.consume_order(w, order, n)
    {lots, next, cargo} = Warehouse.release_cargo(lots(state), w, order.good, n)
    {state |> record_lots(lots) |> save(next) |> apply_transition(transition), cargo}
  end

  def exchange_in(state, %Claim{} = order, cargo, n) do
    w = fetch(state, order.warehouse_id)
    transition = Warehouse.consume_order(w, order, n)
    next = Warehouse.receive_cargo(w, Enum.map(cargo, &CargoRows.coerce/1))
    state |> save(next) |> apply_transition(transition)
  end

  defp apply_transition(state, %Transition{} = transition) do
    state = Enum.reduce(transition.delete, state, &delete(&2, "warehouse_reservations", &1))

    Enum.reduce(transition.put, state, fn r, s ->
      put(s, "warehouse_reservations", r.id, ReservationRows.encode(r))
    end)
  end

  defp lots(state),
    do: %Lots{
      clock_ms: state.clock_ms,
      lot_allocation: Map.get(state, :lot_allocation, {:local, 1})
    }

  defp record_lots(state, %Lots{new_lots: []}), do: state

  defp record_lots(state, %Lots{} = lots),
    do:
      state
      |> Map.put(:lot_allocation, lots.lot_allocation)
      |> Map.update(:new_lots, lots.new_lots, &(&1 ++ lots.new_lots))
end
