defmodule TijaraTides.Domain.WarehouseWorld do
  alias TijaraTides.Domain.Services.WarehouseLiquidation, as: Liquidation
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

    %{
      w
      | reservations: reservations(state, w),
        external_volume:
          shared_external_volume(
            Map.values(entities(state, "warehouses")),
            Map.values(entities(state, "warehouse_reservations")),
            w,
            state.clock_ms
          )
    }
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
    storage_rows(state)
    |> Enum.group_by(&{&1["port"], &1["storage"]})
    |> Map.new(fn {{port, storage}, rows} ->
      {port <> "|" <> storage, footprint(state, rows)}
    end)
  end

  def spare_blocks(state, port, storage),
    do: max(0, pool(storage).blocks - used(state, port, storage))

  def used(state, port, storage),
    do:
      footprint(
        state,
        Enum.filter(storage_rows(state), &(&1["port"] == port && &1["storage"] == storage))
      )

  defp storage_rows(state),
    do:
      Map.values(entities(state, "warehouses")) ++
        Map.values(entities(state, "merchant_warehouses"))

  defp footprint(state, rows) do
    rows
    |> Enum.group_by(&(&1["space_group"] || &1["id"]))
    |> Enum.map(fn {_, group} ->
      if Enum.any?(group, &(&1["space_group"] != nil)) do
        leased =
          Enum.sum(
            for r <- group,
                not r["award_grace"] && r["expires_ms"] > state.clock_ms,
                do: r["blocks"]
          )

        occupied =
          Enum.sum(
            Enum.map(group, fn r ->
              volume = shared_volume(r)

              if r["protected_ms"] > state.clock_ms,
                do: max(volume, r["blocks"] * block_litres()),
                else: volume
            end)
          )

        max(leased, div(occupied + block_litres() - 1, block_litres()))
      else
        Enum.sum(Enum.map(group, & &1["blocks"]))
      end
    end)
    |> Enum.sum()
  end

  defp shared_volume(row),
    do: Enum.sum(for b <- row["cargo"] || [], do: b["quantity"] * row["space_volumes"][b["good"]])

  @doc "Volume in shared allocations that is not covered by another current paid lease."
  def shared_external_volume(rows, claims, w, now) do
    if w.space_group do
      others =
        rows
        |> Enum.filter(&(&1["space_group"] == w.space_group && &1["id"] != w.id))

      occupied = Enum.sum(Enum.map(others, &shared_volume/1))

      reserved =
        Enum.sum(
          for r <- claims,
              r["kind"] == "capacity" && Enum.any?(others, &(&1["id"] == r["warehouse_id"])),
              do: r["quantity"] * w.space_volumes[r["good"]]
        )

      paid =
        Enum.sum(
          for r <- others,
              not r["award_grace"] && r["expires_ms"] > now,
              do: r["blocks"] * block_litres()
        )

      max(0, occupied + reserved - paid)
    else
      0
    end
  end

  @doc "Give each won lot an isolated allocation within its receiving lease's physical space."
  def award_storage(state, warehouse_id, auction_id, cargo, catalogue) do
    w = fetch(state, warehouse_id)
    award_id = "award:" <> auction_id

    if get(state, "warehouses", award_id),
      do: raise(ArgumentError, "Auction allocation already exists")

    volumes = Map.new(catalogue["goods"], fn {id, good} -> {id, good["volume_l"]} end)
    group = w.space_group || w.id
    cargo = Enum.map(cargo, &CargoRows.coerce/1)
    ids = Enum.map(cargo, & &1.lot_id)
    {selected, retained} = Enum.split_with(w.cargo, &(&1.lot_id in ids))

    unless Enum.sum(Enum.map(selected, & &1.quantity)) == Enum.sum(Enum.map(cargo, & &1.quantity)),
      do: raise(ArgumentError, "Won cargo must be received before allocating storage")

    blocks =
      div(
        Enum.sum(for b <- selected, do: b.quantity * volumes[b.good]) + block_litres() - 1,
        block_litres()
      )

    expires = max(state.clock_ms, w.expires_ms + (w.next_days || 0) * @day)

    child = %{
      w
      | id: award_id,
        cargo: selected,
        blocks: blocks,
        prepaid: 0,
        next_rent: 0,
        next_days: nil,
        source_lease_id: w.id,
        space_group: group,
        space_volumes: volumes,
        award_id: auction_id,
        award_grace: true,
        display_number: next_display_number(state, w.company_id),
        renewal_rate: nil,
        auto_days: nil,
        auto_cap: nil,
        expires_ms: expires,
        protected_ms: state.clock_ms,
        grace_rent: if(w.next_days, do: w.next_rent, else: w.rent),
        grace_blocks: w.blocks,
        grace_duration_ms:
          if(w.next_days, do: w.next_days * @day, else: w.expires_ms - w.started_ms)
    }

    state
    |> save(%{w | cargo: retained, space_group: group, space_volumes: volumes})
    |> save(child)
  end

  defp next_display_number(state, company),
    do:
      (owned(state, "warehouses", "company_id", company)
       |> Enum.map(&(&1["display_number"] || 1))
       |> Enum.max(fn -> 0 end)) + 1

  @doc "Quote replacement using occupied blocks exactly once in current utilization."
  def replacement_quote(state, id, days, catalogue) do
    w = fetch(state, id)

    if w && w.award_grace && state.clock_ms >= w.expires_ms &&
         state.clock_ms < w.expires_ms + w.grace_ms && days in @terms do
      blocks = div(Warehouse.volume(w, catalogue) + block_litres() - 1, block_litres())

      if blocks > 0,
        do: %{
          blocks: blocks,
          rent: quote(max(0, used(state, w.port, w.storage) - blocks), w.storage, blocks, days)
        }
    end
  end

  def replace_award(state, account, cmd, lease_id, catalogue) do
    w = fetch(state, cmd["warehouse"])
    offer = replacement_quote(state, cmd["warehouse"], cmd["days"], catalogue)
    company = w && get(state, "companies", w.company_id)

    cond do
      is_nil(w) or w.company_id != account["company_id"] ->
        {:error, :warehouse_invalid}

      is_nil(lease_id) or get(state, "warehouses", lease_id) != nil ->
        {:error, :warehouse_invalid}

      is_nil(offer) or w.protected_ms > state.clock_ms ->
        {:error, :warehouse_replacement_closed}

      company["bankruptcy_ms"] != nil ->
        {:error, :finance_no_company}

      cmd["price"] != offer.rent ->
        {:error, :price_changed}

      true ->
        candidate = Liquidation.prepare(state, w, catalogue)
        p = Liquidation.pool(candidate, w.id)
        charges = p["rent_due"] + p["handling_due"]

        if p["status"] != "grace" do
          {:error, :warehouse_replacement_closed}
        else
          if company["unpaid"] > 0 || company["cash"] - company["reserved"] < offer.rent + charges do
            {:error, :insufficient_cash}
          else
            next = %{
              w
              | id: lease_id,
                blocks: offer.blocks,
                started_ms: state.clock_ms,
                expires_ms: state.clock_ms + cmd["days"] * @day,
                rent: offer.rent,
                prepaid: offer.rent,
                award_grace: false,
                source_lease_id: nil,
                grace_rent: nil,
                grace_blocks: nil,
                grace_duration_ms: nil
            }

            changed =
              candidate
              |> TijaraTides.Domain.WarehouseLiquidationWorld.replace(w.id, charges)
              |> save(next)
              |> relocate_award(w.id, next.id)
              |> CompanyFinanceWorld.post(w.company_id, "warehouse_replacement", [
                {"prepaid_rent", offer.rent},
                {"rent_expense", charges},
                {"cash_available", -offer.rent - charges}
              ])

            {:ok, changed, %{"charges" => charges}}
          end
        end
    end
  end

  defp relocate_award(state, old, new) do
    state =
      Enum.reduce(entities(state, "warehouse_reservations"), state, fn {id, row}, s ->
        if row["warehouse_id"] == old,
          do: put(s, "warehouse_reservations", id, %{row | "warehouse_id" => new}),
          else: s
      end)

    state
    |> TijaraTides.Domain.OrderBookWorld.relocate_storage(old, new)
    |> TijaraTides.Domain.AuctionWorld.relocate_storage(old, new)
    |> delete("warehouses", old)
  end

  defp synchronize_awards(state) do
    Enum.reduce(entities(state, "warehouses"), state, fn {_, row}, s ->
      if row["award_grace"] do
        parent = get(s, "warehouses", row["source_lease_id"])
        w = fetch(s, row["id"])

        if parent && Warehouse.covered_until(snapshot(parent)) > w.expires_ms &&
             not Liquidation.active?(s, w.id) do
          covered = Warehouse.covered_until(snapshot(parent))
          basis_rent = if parent["next_days"], do: parent["next_rent"], else: parent["rent"]

          duration =
            if parent["next_days"],
              do: parent["next_days"] * @day,
              else: parent["expires_ms"] - parent["started_ms"]

          save(s, %{
            w
            | expires_ms: covered,
              grace_rent: basis_rent,
              grace_blocks: parent["blocks"],
              grace_duration_ms: duration
          })
        else
          s
        end
      else
        s
      end
    end)
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

      get(state, "warehouses", id) != nil or Liquidation.pool(state, id) != nil ->
        {:error, :warehouse_invalid}

      true ->
        w =
          %Warehouse{
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
            aging_bps: TijaraTides.Domain.CargoFreshness.rate("reefer", catalogue),
            good: if(storage == "liquid", do: cmd["good"]),
            blocks: cmd["blocks"],
            started_ms: state.clock_ms,
            expires_ms: state.clock_ms + cmd["days"] * @day,
            rent: price,
            prepaid: price,
            protected_ms: state.clock_ms
          }
          |> struct!(Liquidation.terms(catalogue))

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

        w.award_grace or not Warehouse.releasable?(w, blocks, state.clock_ms, catalogue) ->
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

  # Validation probes may ignore admission, but their returned state is discarded.
  def transfer(state, account, cmd, catalogue, admission \\ :normal) do
    minimum = Map.get(cmd, "min_remaining_ms", 0)

    with %{"company_id" => owner} = row <- get(state, "warehouses", cmd["warehouse"]),
         true <- owner == account["company_id"],
         %{"company_id" => ^owner, "status" => "docked"} = ship <-
           get(state, "ships", cmd["ship"]),
         true <- ship["port"] == row["port"],
         %{} = item <- catalogue["goods"][cmd["good"]],
         n when is_integer(n) and n > 0 and n <= @max_lots <- cmd["quantity"],
         side when side in ["store", "collect"] <- cmd["side"],
         true <- CargoRules.valid_remaining?(minimum) do
      w = load(state, row)
      company = get(state, "companies", owner)

      cleaning = if side == "collect", do: cleaning_cost(ship, item), else: 0

      fee =
        cleaning +
          n * TijaraTides.Domain.PortCargoMarket.handling_rate(catalogue["ports"][w.port])

      # Collection offers only unspoiled lots, so take/4 must walk that same list: given the
      # whole manifest it matches on good alone and drains expired batches the count excluded.
      {fresh, _stale} =
        Enum.split_with(
          w.cargo,
          &CargoRules.qualifies_batch?(
            &1,
            state.clock_ms,
            minimum,
            CargoRules.hold_rate(ship, catalogue)
          )
        )

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

        state.clock_ms >= w.expires_ms + w.grace_ms ->
          {:error, :warehouse_expired}

        side == "store" and (w.award_grace or state.clock_ms >= w.expires_ms) ->
          {:error, :warehouse_expired}

        not compatible?(w, item) or not CargoRules.compatible_cargo?(ship, item) ->
          {:error, :incompatible_cargo}

        available < n ->
          {:error, :insufficient_cargo}

        side == "store" and
            volume(w, catalogue) + w.external_volume +
              reserved_volume(state, w, catalogue, ship["id"], item["id"]) +
              n * item["volume_l"] > w.blocks * block_litres() ->
          {:error, :warehouse_capacity}

        side == "collect" and not fits?(ship, item, n, catalogue) ->
          {:error, :capacity_exceeded}

        company["cash"] - company["reserved"] < fee or company["unpaid"] > 0 ->
          {:error, :insufficient_cash}

        admission != :validate and not PortBerthsWorld.available?(state, ship, catalogue) ->
          {:error, :warehouse_berth_busy}

        true ->
          state = Liquidation.before_remove(state, w.id)

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
              {s, cargo} =
                ShipWorld.unload_cargo(state, ship["id"], item["id"], n, nil, catalogue)

              {s, receive_conditioned(w, cargo, state.clock_ms)}
            else
              {lots, next, cargo} =
                Warehouse.release_cargo(
                  lots(state),
                  w,
                  item["id"],
                  n,
                  minimum,
                  CargoRules.hold_rate(ship, catalogue)
                )

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
              [
                {"handling_expense", fee},
                {"cash_available", -fee}
              ],
              %{ship: ship["id"], good: item["id"]}
            )

          {:ok, Liquidation.refresh(state, w.id, catalogue), %{}}
      end
    else
      _ -> {:error, :warehouse_invalid}
    end
  end

  def cleaning_cost(ship, item), do: Warehouse.cleaning_cost(ship["last_liquid"], item)

  defp fits?(ship, item, n, catalogue) do
    used = TijaraTides.Domain.Ship.capacity(TijaraTides.Domain.Ship.Rows.decode(ship), catalogue)
    class = TijaraTides.Domain.ShipClass.all()[ship["class"]]

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
    state = synchronize_awards(state)

    Enum.reduce(Enum.sort(Map.keys(entities(state, "warehouses"))), state, fn id, state ->
      row = get(state, "warehouses", id)
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
            {"warehouse.expired",
             %{
               "port" => w.port,
               "minutes" => div(w.grace_ms, 60_000),
               "grace_rate" =>
                 div(w.rent * @day, max(1, (w.expires_ms - w.started_ms) * w.blocks)),
               "liquidation_rate" =>
                 div(
                   w.rent * @day * (10_000 + w.surcharge_bps),
                   max(1, (w.expires_ms - w.started_ms) * w.blocks * 10_000)
                 )
             }}
          )
        else
          state
        end

      state = Liquidation.prepare(state, w, catalogue)
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

      if settlement =
           if(bankrupt and not Liquidation.active?(state, w.id),
             do: Warehouse.clearance(w, state.clock_ms, true, catalogue)
           ) do
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
        state |> save(w) |> Liquidation.advance(w.id, catalogue)
      end
    end)
  end

  alias TijaraTides.Domain.Warehouse.Reservation

  def reservations(state, w) when is_map(state) do
    reservations(owned(state, "warehouse_reservations", "company_id", w.company_id), w)
    |> Enum.map(fn r ->
      auction = r.auction_id && get(state, "auctions", r.auction_id)
      %{r | expires_ms: if(auction, do: auction["expires_ms"])}
    end)
  end

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
  def collection_source(state, ship, good, minimum \\ 0, catalogue \\ %{}) do
    owned(state, "warehouses", "company_id", ship["company_id"])
    |> Enum.filter(&(&1["port"] == ship["port"]))
    |> Enum.map(&load(state, &1))
    |> Enum.filter(fn w ->
      state.clock_ms < w.expires_ms + w.grace_ms and
        Enum.sum(
          for b <- w.cargo,
              b.good == good and
                CargoRules.qualifies_batch?(
                  b,
                  state.clock_ms,
                  minimum,
                  CargoRules.hold_rate(ship, catalogue)
                ),
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
          &(&1.good == good and
              CargoRules.qualifies_batch?(
                &1,
                state.clock_ms,
                minimum,
                CargoRules.hold_rate(ship, catalogue)
              ))
        )
        |> Enum.map(&(&1.expires_ms || 9_223_372_036_854_775_807))
        |> Enum.min()

      {if(own, do: 0, else: 1), expiry, w.id}
    end)
    |> List.first()
  end

  @doc "Earmark a committed remote fill; its incoming capacity has already been consumed."
  def earmark_remote_fill(state, link, order, quantity, catalogue) do
    id = "linked:" <> link["order_id"]
    w = fetch(state, order.warehouse_id)
    old = get(state, "warehouse_reservations", id)

    r = %Reservation{
      id: id,
      warehouse_id: w.id,
      company_id: w.company_id,
      ship_id: link["ship_id"],
      stop_id: link["stop_id"],
      good: order.good,
      kind: "stock",
      quantity: quantity + if(old, do: old["quantity"], else: 0),
      created_ms: if(old, do: old["created_ms"], else: state.clock_ms)
    }

    w = %{w | reservations: Enum.reject(w.reservations, &(&1.id == id))}
    apply_transition(state, Warehouse.earmark_fill(w, r, state.clock_ms, catalogue))
  end

  def release_link_stock(state, ship, stop, good, keep \\ 0) do
    claims =
      entities(state, "warehouse_reservations")
      |> Map.values()
      |> Enum.filter(
        &(&1["ship_id"] == ship and &1["stop_id"] == stop and &1["good"] == good and
            String.starts_with?(&1["id"], "linked:"))
      )
      |> Enum.sort_by(&{&1["created_ms"], &1["id"]})

    Enum.reduce(claims, {state, keep}, fn row, {s, remaining} ->
      n = min(row["quantity"], remaining)

      s =
        if n == 0,
          do: delete(s, "warehouse_reservations", row["id"]),
          else: put(s, "warehouse_reservations", row["id"], %{row | "quantity" => n})

      {s, remaining - n}
    end)
    |> elem(0)
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
             r["bid_id"] != nil or String.starts_with?(id, "linked:"),
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
            (get(s, "companies", w.company_id)["bankruptcy_ms"] == nil or r.auction_id != nil)

        if valid, do: MapSet.put(ids, r.id), else: ids
      end)

    transition =
      Warehouse.prune_reservations(
        %{w | reservations: reservations(state, w)},
        state.clock_ms,
        valid_ids
      )

    state
    |> apply_transition(transition)
    |> notify_released(w, Enum.map(transition.put, & &1.id) ++ transition.delete)
  end

  @doc "Receivership ends every claim except the receiver's own auction lots."
  def release_insolvent_claims(state, company_id),
    do: release_claims(state, company_id, &is_nil(&1.auction_id))

  @doc "A ship leaving its owner's fleet stops holding stock or receiving space."
  def release_ship_claims(state, ship_id) do
    case get(state, "ships", ship_id) do
      nil ->
        state

      ship ->
        release_claims(state, ship["company_id"], fn r ->
          r.ship_id == ship_id and is_nil(r.order_id) and is_nil(r.auction_id) and
            is_nil(r.bid_id)
        end)
    end
  end

  @doc "Claims made for a route stop end with that stop."
  def release_stop_claims(state, _company_id, []), do: state

  def release_stop_claims(state, company_id, stop_ids) do
    removed = MapSet.new(stop_ids)

    release_claims(
      state,
      company_id,
      &(&1.stop_id != nil and MapSet.member?(removed, &1.stop_id))
    )
  end

  defp release_claims(state, company_id, released?) do
    Enum.reduce(owned(state, "warehouses", "company_id", company_id), state, fn row, s ->
      w = load(s, row)

      case for(r <- w.reservations, released?.(r), do: r.id) do
        [] ->
          s

        ids ->
          s
          |> apply_transition(Warehouse.release_reservations(w, ids))
          |> notify_released(w, Enum.reject(ids, &String.starts_with?(&1, "linked:")))
      end
    end)
  end

  defp notify_released(state, w, ids) do
    account = get(state, "companies", w.company_id)["account_id"]

    Enum.reduce(ids, state, fn id, s ->
      TijaraTides.Domain.Notices.notice(
        s,
        account,
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
          {:ok, synchronize_awards(save(state, w)), %{}}
      end
    else
      _ -> {:error, :warehouse_invalid}
    end
  end

  def renewal_settings(state, account, cmd) do
    with %{"company_id" => owner, "award_grace" => false} = row <-
           get(state, "warehouses", cmd["warehouse"]),
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

  @doc "Receiver extensions charge available estate cash only before lease liquidation starts."
  def estate_cover(state, id, until_ms) do
    w = fetch(state, id)

    if Liquidation.active?(state, id) or
         (Warehouse.covered_until(w) > until_ms and w.expires_ms > state.clock_ms) do
      state
    else
      days = max(1, div(max(until_ms, state.clock_ms) - w.expires_ms, @day) + 1)
      rate = Warehouse.extension_rate(w, used(state, w.port, w.storage))
      charge = days * rate
      state = CompanyFinanceWorld.estate_expense(state, w.company_id, charge, "rent_expense")
      # The receiver pays the extension as an expense, keeping existing prepaid terms intact.
      save(state, %{w | expires_ms: w.expires_ms + days * @day, auto_days: nil, auto_cap: nil})
    end
  end

  def estate_unload(state, ship, item, catalogue) do
    available_blocks = max(0, pool(item["hold"]).blocks - used(state, ship["port"], item["hold"]))

    quantity =
      min(
        ShipWorld.cargo_available(state, ship["id"], item["id"]),
        div(available_blocks * block_litres(), item["volume_l"])
      )

    blocks = div(quantity * item["volume_l"] + block_litres() - 1, block_litres())
    price = quote(used(state, ship["port"], item["hold"]), item["hold"], blocks, 3)

    if (quantity > 0 and price) && PortBerthsWorld.available?(state, ship, catalogue) do
      id = "estate-storage:#{ship["id"]}:#{item["id"]}:#{state.clock_ms}"

      w = %Warehouse{
        id: id,
        company_id: ship["company_id"],
        port: ship["port"],
        storage: item["hold"],
        good: if(item["hold"] == "liquid", do: item["id"]),
        blocks: blocks,
        started_ms: state.clock_ms,
        expires_ms: state.clock_ms + 3 * @day,
        rent: price,
        prepaid: price,
        protected_ms: state.clock_ms
      }

      state =
        state
        |> save(w)
        |> CompanyFinanceWorld.estate_expense(w.company_id, price, "prepaid_rent")

      {state, cargo} =
        ShipWorld.unload_cargo(state, ship["id"], item["id"], quantity, nil, catalogue)

      w = receive_conditioned(w, cargo, state.clock_ms)
      w = Warehouse.protect_handling(w, get(state, "ships", ship["id"])["arrive_ms"])

      fee =
        quantity * TijaraTides.Domain.PortCargoMarket.handling_rate(catalogue["ports"][w.port])

      state
      |> save(w)
      |> ShipWorld.admit_handling(ship["id"])
      |> CompanyFinanceWorld.estate_expense(w.company_id, fee, "handling_expense")
    else
      state
    end
  end

  def back_order(state, %Claim{} = order, catalogue) do
    if order.liquidation and not Liquidation.active?(state, order.warehouse_id),
      do: raise(ArgumentError, "Liquidation claim requires an active pool")

    case Warehouse.back_order(fetch(state, order.warehouse_id), order, state.clock_ms, catalogue) do
      {:ok, transition} -> {:ok, apply_transition(state, transition)}
      error -> error
    end
  end

  def release_trade(state, %Claim{} = order),
    do: delete(state, "warehouse_reservations", Claim.reservation_id(order))

  def order_backed?(state, %Claim{} = order) do
    case fetch(state, order.warehouse_id) do
      nil ->
        false

      w ->
        (not order.liquidation or Liquidation.active?(state, w.id)) and
          Warehouse.order_backed?(w, order, state.clock_ms)
    end
  end

  def exchange_ready?(state, %Claim{} = order) do
    row = get(state, "warehouses", order.warehouse_id)
    order_backed?(state, order) && row["protected_ms"] <= state.clock_ms
  end

  def exchange_out(state, %Claim{} = order, n) do
    state = Liquidation.before_remove(state, order.warehouse_id)
    w = fetch(state, order.warehouse_id)
    transition = Warehouse.consume_order(w, order, n)

    {lots, next, cargo} =
      if order.liquidation,
        do: Warehouse.release_liquidation_cargo(lots(state), w, order, n),
        else: Warehouse.release_claim_cargo(lots(state), w, order, n)

    {state |> record_lots(lots) |> save(next) |> apply_transition(transition), cargo}
  end

  @doc "Expired allocations follow actual occupied space without changing their snapshotted rate."
  def resize_expired(state, id, blocks) do
    w = fetch(state, id)

    unless state.clock_ms >= w.expires_ms and blocks >= 0 and blocks <= w.blocks,
      do: raise(ArgumentError, "Expired allocations can only shrink")

    save(state, %{w | blocks: blocks})
  end

  def release_collection_claims(state, id) do
    w = fetch(state, id)

    reservations(state, w)
    |> Enum.filter(&(&1.auction_id == nil))
    |> Enum.reduce(state, fn r, s ->
      s
      |> delete("warehouse_reservations", r.id)
      |> TijaraTides.Domain.Notices.notice(
        get(s, "companies", w.company_id)["account_id"],
        "reservation:" <> r.id,
        {"warehouse.reservation_released", %{"port" => w.port}}
      )
    end)
  end

  def release_liquidated(state, id) do
    w = fetch(state, id)

    unless w.cargo == [] and w.reservations == [] and
             get(state, "warehouse_liquidations", id)["status"] == "completed",
           do: raise(ArgumentError, "Lease release requires a completed empty liquidation")

    delete(state, "warehouses", id)
  end

  def liquidation_out(state, id, good, n, lot_ids \\ nil) do
    w = fetch(state, id)

    unless Liquidation.active?(state, id) and n <= Liquidation.available(state, id, good),
      do: raise(ArgumentError, "Liquidation exceeds unreserved cargo")

    {lots, next, cargo} = Warehouse.release_free_cargo(lots(state), w, good, n, lot_ids)
    {state |> record_lots(lots) |> save(next), cargo}
  end

  def order_cargo(state, claim) do
    w = fetch(state, claim.warehouse_id)

    if w,
      do:
        Warehouse.cargo_allocations(w, claim.good, state.clock_ms)
        |> elem(0)
        |> Map.get(Claim.reservation_id(claim), []),
      else: []
  end

  def receiving_bps(state, warehouse) do
    w = fetch(state, warehouse)
    if w && w.storage == "reefer", do: w.aging_bps, else: 10_000
  end

  def exchange_in(state, %Claim{} = order, cargo, n) do
    w = fetch(state, order.warehouse_id)
    transition = Warehouse.consume_order(w, order, n)
    next = receive_conditioned(w, cargo, state.clock_ms)
    state |> save(next) |> apply_transition(transition)
  end

  defp receive_conditioned(w, cargo, now) do
    rate = if w.storage == "reefer", do: w.aging_bps, else: 10_000

    Warehouse.receive_cargo(
      w,
      Enum.map(cargo, fn row ->
        row |> CargoRows.coerce() |> TijaraTides.Domain.CargoFreshness.recondition(now, rate)
      end)
    )
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
