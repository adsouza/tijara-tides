defmodule TijaraTides.Domain.Warehouse do
  @moduledoc "Finite port storage leases with typed cargo, prepaid rent and preserved lot identity."
  import TijaraTides.Domain.State
  alias TijaraTides.Domain.{CompanyFinance, Ship, CargoRules, PortBerths}
  alias TijaraTides.Domain.Ship.CargoBatch
  @day 86_400_000
  @terms [1, 3, 7]
  @storage_classes ["dry", "reefer", "liquid"]
  @max_lots CargoRules.max_lots()
  @fields ~w(id company_id port storage good blocks started_ms expires_ms rent prepaid protected_ms)a
  @renewal_defaults [
    renewal_rate: nil,
    next_rent: 0,
    next_days: nil,
    auto_days: nil,
    auto_cap: nil
  ]
  @enforce_keys @fields
  defstruct @fields ++ @renewal_defaults ++ [cargo: []]

  def from_row(row) do
    unknown =
      Map.keys(row) --
        ["cargo" | Enum.map(@fields ++ Keyword.keys(@renewal_defaults), &Atom.to_string/1)]

    if unknown != [], do: raise(ArgumentError, "Unknown warehouse fields")

    struct!(
      __MODULE__,
      Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))})
      |> Map.merge(
        Map.new(@renewal_defaults, fn {k, v} -> {k, Map.get(row, Atom.to_string(k), v)} end)
      )
      |> Map.put(:cargo, Enum.map(row["cargo"], &CargoBatch.from_row/1))
    )
  end

  def to_row(w),
    do:
      Map.new(
        @fields ++ Keyword.keys(@renewal_defaults),
        &{Atom.to_string(&1), Map.fetch!(w, &1)}
      )
      |> Map.put("cargo", Enum.map(w.cargo, &CargoBatch.to_row/1))

  defp save(state, w), do: put(state, "warehouses", w.id, to_row(w))
  def block_litres, do: 100_000
  def terms, do: @terms
  def pool("dry"), do: %{blocks: 1000, rate: 100}
  def pool("reefer"), do: %{blocks: 250, rate: 300}
  def pool("liquid"), do: %{blocks: 500, rate: 200}
  def pool(_), do: nil

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

  # Marginal block prices rise quadratically with utilization; integers are cents.
  def quote(used, storage, blocks, days)
      when storage in @storage_classes and is_integer(blocks) and blocks > 0 and
             days in @terms do
    p = pool(storage)

    if used + blocks <= p.blocks do
      Enum.sum(
        for n <- (used + 1)..(used + blocks),
            do: days * div(p.rate * (p.blocks * p.blocks + 4 * n * n), p.blocks * p.blocks)
      )
    end
  end

  def quote(_, _, _, _), do: nil

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
        w = %__MODULE__{
          id: id,
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
          |> CompanyFinance.post(company["id"], "warehouse_lease", [
            {"prepaid_rent", price},
            {"cash_available", -price}
          ])

        {:ok, state, %{}}
    end
  end

  def volume(w, catalogue),
    do: Enum.sum(for b <- w.cargo, do: b.quantity * catalogue["goods"][b.good]["volume_l"])

  def compatible?(w, item),
    do: item["hold"] == w.storage and (w.storage != "liquid" or item["id"] == w.good)

  def release(state, account, id, blocks, catalogue) do
    with %{"company_id" => owner} = row <- get(state, "warehouses", id),
         true <- owner == account["company_id"],
         true <- is_integer(blocks) and blocks > 0 and blocks <= row["blocks"] do
      company = get(state, "companies", owner)
      w = from_row(row)

      cond do
        is_nil(company) or company["bankruptcy_ms"] != nil ->
          {:error, :finance_no_company}

        company["unpaid"] > 0 ->
          {:error, :insufficient_cash}

        state.clock_ms < w.protected_ms or
          w.next_days != nil or
            volume(w, catalogue) + reserved_volume(state, w, catalogue) >
              (w.blocks - blocks) * block_litres() ->
          {:error, :warehouse_occupied}

        true ->
          {state, w} = accrue(state, w)
          remaining_rent = div(w.rent * (w.blocks - blocks), w.blocks)

          remaining_prepaid =
            div(
              remaining_rent * max(0, w.expires_ms - state.clock_ms),
              max(1, w.expires_ms - w.started_ms)
            )

          forfeited = w.prepaid - remaining_prepaid
          refund = div(forfeited, 2)

          state =
            CompanyFinance.post(state, owner, "warehouse_release", [
              {"prepaid_rent", -forfeited},
              {"cash_available", refund},
              {"rent_expense", forfeited - refund}
            ])

          state =
            if blocks == w.blocks,
              do: state |> clear_reservations(w) |> delete("warehouses", id),
              else:
                save(state, %{
                  w
                  | blocks: w.blocks - blocks,
                    rent: remaining_rent,
                    renewal_rate:
                      if(w.renewal_rate, do: div(w.renewal_rate * (w.blocks - blocks), w.blocks)),
                    prepaid: remaining_prepaid
                })

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
      w = from_row(row)
      company = get(state, "companies", owner)

      cleaning = if side == "collect", do: cleaning_cost(ship, item), else: 0

      fee =
        cleaning +
          n * TijaraTides.Domain.PortCargoMarket.handling_rate(catalogue["ports"][w.port])

      # Collection offers only unspoiled lots, so take/4 must walk that same list: given the
      # whole manifest it matches on good alone and drains expired batches the count excluded.
      {fresh, stale} =
        Enum.split_with(w.cargo, &(is_nil(&1.expires_ms) or &1.expires_ms > state.clock_ms))

      available =
        if side == "store",
          do: Ship.cargo_available(state, ship["id"], item["id"]),
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

        not PortBerths.available?(state, ship, catalogue) ->
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
              {s, cargo} = Ship.unload_cargo(state, ship["id"], item["id"], n)
              {s, %{w | cargo: w.cargo ++ Enum.map(cargo, &CargoBatch.from_row/1)}}
            else
              {s, cargo, left} = CargoBatch.take(state, fresh, n, item["id"])

              {Ship.load_cargo(
                 s,
                 ship["id"],
                 Enum.map(cargo, &CargoBatch.to_row/1),
                 cleaning,
                 catalogue
               ), %{w | cargo: left ++ stale}}
            end

          w = %{w | protected_ms: get(state, "ships", ship["id"])["arrive_ms"]}

          state =
            save(state, w)
            |> Ship.admit_handling(ship["id"])
            |> CompanyFinance.post(
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

  def cleaning_cost(ship, item) do
    if item["hold"] == "liquid" and ship["last_liquid"] not in [nil, item["id"]],
      do: if("vegetable_oil" in [ship["last_liquid"], item["id"]], do: 25_000, else: 5000),
      else: 0
  end

  defp fits?(ship, item, n, catalogue) do
    used = TijaraTides.Domain.Fleet.capacity(ship, catalogue)
    class = TijaraTides.Domain.Fleet.classes()[ship["class"]]

    used.weight + n * item["weight_kg"] <= class["weight"] and
      used.volume + n * item["volume_l"] <= class["volume"]
  end

  defp accrue(state, w) do
    remaining =
      if w.expires_ms <= w.started_ms,
        do: 0,
        else: div(w.rent * max(0, w.expires_ms - state.clock_ms), w.expires_ms - w.started_ms)

    amount = w.prepaid - remaining

    {CompanyFinance.post(state, w.company_id, "warehouse_rent", [
       {"prepaid_rent", -amount},
       {"rent_expense", amount}
     ]), %{w | prepaid: remaining}}
  end

  def advance(state, catalogue) do
    Enum.reduce(entities(state, "warehouses"), state, fn {_, row}, state ->
      {state, w} = roll_term(state, from_row(row))
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

      {expired, cargo} =
        Enum.split_with(w.cargo, &(&1.expires_ms != nil and &1.expires_ms <= state.clock_ms))

      lost = Enum.sum(for b <- expired, do: b.quantity * b.unit_cost)

      state =
        if lost > 0,
          do:
            CompanyFinance.post(state, w.company_id, "warehouse_spoilage", [
              {"inventory", -lost},
              {"spoilage_expense", lost}
            ]),
          else: state

      w = %{w | cargo: cargo}
      bankrupt = get(state, "companies", w.company_id)["bankruptcy_ms"] != nil

      if state.clock_ms >= w.protected_ms and
           (state.clock_ms >= w.expires_ms + div(@day, 2) or bankrupt) do
        # System clearance is the initial liquidation adapter; auctions come later. It faces
        # no buyer, so it has neither depth nor slippage and would otherwise be a fixed price
        # floor: cap proceeds at cost so abandoning stock can never mint cash when a port's
        # ask has drifted below half reference.
        cost = Enum.sum(for b <- cargo, do: b.quantity * b.unit_cost)

        value =
          Enum.sum(
            for b <- cargo,
                do:
                  b.quantity *
                    min(b.unit_cost, div(catalogue["goods"][b.good]["reference_cents"], 2))
          )

        grace =
          div(w.rent * max(0, state.clock_ms - w.expires_ms), max(1, w.expires_ms - w.started_ms))

        charges = min(value, grace)

        state
        |> TijaraTides.Domain.Notices.notice(
          get(state, "companies", w.company_id)["account_id"],
          "warehouse:" <> w.id,
          {"warehouse.cleared", %{"port" => w.port, "refund" => value - charges}}
        )
        |> clear_reservations(w)
        |> delete("warehouses", w.id)
        |> CompanyFinance.post(w.company_id, "warehouse_clearance", [
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
    |> Enum.map(&Reservation.from_row/1)
    |> Enum.sort_by(&{&1.created_ms, &1.id})
  end

  # A reservation occupies no extra volume for stock already in the building.
  def reserved_volume(state, w, catalogue, ship_id \\ nil, good \\ nil) do
    Enum.sum(
      for r <- reservations(state, w),
          r.kind == "capacity",
          not (r.ship_id == ship_id and r.good == good),
          do: r.quantity * catalogue["goods"][r.good]["volume_l"]
    )
  end

  def reserved_quantity(state, w, kind, good, except_ship \\ nil) do
    Enum.sum(
      for r <- reservations(state, w),
          r.kind == kind and r.good == good and r.ship_id != except_ship,
          do: r.quantity
    )
  end

  @doc "Choose this ship's earmarked stock first, then other available owned stock."
  def collection_source(state, ship, good) do
    owned(state, "warehouses", "company_id", ship["company_id"])
    |> Enum.filter(&(&1["port"] == ship["port"]))
    |> Enum.map(&from_row/1)
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
      w = from_row(row)

      available =
        Enum.sum(
          for b <- w.cargo,
              b.good == item["id"] and (is_nil(b.expires_ms) or b.expires_ms > state.clock_ms),
              do: b.quantity
        )

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

        length(reservations(state, w)) >= 100 ->
          {:error, :warehouse_capacity}

        kind == "stock" and n + reserved_quantity(state, w, kind, item["id"]) > available ->
          {:error, :insufficient_cargo}

        kind == "capacity" and
            volume(w, catalogue) + reserved_volume(state, w, catalogue) + n * item["volume_l"] >
              w.blocks * block_litres() ->
          {:error, :warehouse_capacity}

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

          {:ok, put(state, "warehouse_reservations", id, Reservation.to_row(r)), %{}}
      end
    else
      _ -> {:error, :warehouse_invalid}
    end
  end

  def cancel_reservation(state, account, id) do
    case get(state, "warehouse_reservations", id) do
      %{"company_id" => owner} ->
        if owner != account["company_id"],
          do: {:error, :warehouse_invalid},
          else: {:ok, delete(state, "warehouse_reservations", id), %{}}

      _ ->
        {:error, :warehouse_invalid}
    end
  end

  defp consume_reservations(state, w, ship_id, good, kind, quantity) do
    {state, _} =
      Enum.reduce(reservations(state, w), {state, quantity}, fn r, {s, n} ->
        if r.ship_id == ship_id and r.good == good and r.kind == kind and n > 0 do
          taken = min(n, r.quantity)

          next =
            if taken == r.quantity,
              do: delete(s, "warehouse_reservations", r.id),
              else:
                put(
                  s,
                  "warehouse_reservations",
                  r.id,
                  Reservation.to_row(%{r | quantity: r.quantity - taken})
                )

          {next, n - taken}
        else
          {s, n}
        end
      end)

    state
  end

  defp clear_reservations(state, w) do
    Enum.reduce(reservations(state, w), state, &delete(&2, "warehouse_reservations", &1.id))
  end

  # Also called after commands so sold ships and removed stops never leave dangling claims.
  def reconcile_reservations(state, catalogue, company_id) do
    Enum.reduce(owned(state, "warehouses", "company_id", company_id), state, fn row, s ->
      prune_reservations(s, from_row(row), catalogue)
    end)
  end

  defp prune_reservations(state, w, _catalogue) do
    available =
      w.cargo
      |> Enum.filter(&(is_nil(&1.expires_ms) or &1.expires_ms > state.clock_ms))
      |> Enum.group_by(& &1.good)
      |> Map.new(fn {g, bs} -> {g, Enum.sum(Enum.map(bs, & &1.quantity))} end)

    {state, _} =
      Enum.reduce(reservations(state, w), {state, available}, fn r, {s, stock} ->
        ship = get(s, "ships", r.ship_id)
        stop = r.stop_id && get(s, "route_stops", r.stop_id)

        valid =
          ship && ship["company_id"] == w.company_id &&
            (is_nil(r.stop_id) or (stop && stop["ship_id"] == r.ship_id && stop["port"] == w.port)) &&
            (r.kind == "stock" or state.clock_ms < w.expires_ms) &&
            get(s, "companies", w.company_id)["bankruptcy_ms"] == nil

        n =
          if valid,
            do:
              if(r.kind == "stock",
                do: min(r.quantity, Map.get(stock, r.good, 0)),
                else: r.quantity
              ),
            else: 0

        s =
          cond do
            n == 0 ->
              delete(s, "warehouse_reservations", r.id)

            n < r.quantity ->
              put(s, "warehouse_reservations", r.id, Reservation.to_row(%{r | quantity: n}))

            true ->
              s
          end

        s =
          if n < r.quantity,
            do:
              TijaraTides.Domain.Notices.notice(
                s,
                get(s, "companies", w.company_id)["account_id"],
                "reservation:" <> r.id,
                {"warehouse.reservation_released", %{"port" => w.port}}
              ),
            else: s

        {s, if(r.kind == "stock", do: Map.update(stock, r.good, 0, &(&1 - n)), else: stock)}
      end)

    state
  end

  def renewal_window_ms, do: 21_600_000

  def renewal_open?(w, now),
    do: now >= w.expires_ms - renewal_window_ms() and now < w.expires_ms and is_nil(w.next_days)

  defp lock_quote(state, w) do
    if is_nil(w.renewal_rate) and renewal_open?(w, state.clock_ms) do
      %{
        w
        | renewal_rate:
            quote(max(0, used(state, w.port, w.storage) - w.blocks), w.storage, w.blocks, 1)
      }
    else
      w
    end
  end

  def renew(state, account, cmd) do
    with %{"company_id" => owner} = row <- get(state, "warehouses", cmd["warehouse"]),
         true <- owner == account["company_id"],
         days when days in @terms <- cmd["days"] do
      w = lock_quote(state, from_row(row))
      company = get(state, "companies", owner)
      price = w.renewal_rate && w.renewal_rate * days

      cond do
        company["bankruptcy_ms"] != nil ->
          {:error, :finance_no_company}

        not renewal_open?(w, state.clock_ms) ->
          {:error, :warehouse_renewal_closed}

        price != cmd["price"] ->
          {:error, :price_changed}

        company["unpaid"] > 0 or company["cash"] - company["reserved"] < price ->
          {:error, :insufficient_cash}

        true ->
          {state, w} = pay_renewal(state, w, days)
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
      w = from_row(row)

      w =
        if cmd["days"] == 0,
          do: %{w | auto_days: nil, auto_cap: nil},
          else: %{w | auto_days: cmd["days"], auto_cap: cmd["price"]}

      {state, w} = prepare_renewal(state, w)
      {:ok, save(state, w), %{}}
    else
      _ -> {:error, :warehouse_invalid}
    end
  end

  defp pay_renewal(state, w, days) do
    price = w.renewal_rate * days

    state =
      CompanyFinance.post(state, w.company_id, "warehouse_renewal", [
        {"prepaid_rent", price},
        {"cash_available", -price}
      ])

    {state, %{w | next_rent: price, next_days: days}}
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
    if state.clock_ms >= w.expires_ms and w.next_days != nil and
         get(state, "companies", w.company_id)["bankruptcy_ms"] == nil do
      state =
        CompanyFinance.post(state, w.company_id, "warehouse_rent", [
          {"prepaid_rent", -w.prepaid},
          {"rent_expense", w.prepaid}
        ])

      {state,
       %{
         w
         | started_ms: w.expires_ms,
           expires_ms: w.expires_ms + w.next_days * @day,
           rent: w.next_rent,
           prepaid: w.next_rent,
           next_rent: 0,
           next_days: nil,
           renewal_rate: nil
       }}
    else
      {state, w}
    end
  end
end
