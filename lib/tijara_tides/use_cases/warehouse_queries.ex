defmodule TijaraTides.UseCases.WarehouseQueries do
  alias TijaraTides.Domain.WarehouseWorld
  @moduledoc "Warehouse lease and transfer options from authorized read models."
  alias TijaraTides.Domain.{CargoRules, Warehouse}

  def warehouse_options(definitions, view, port, draft, ship) do
    catalogue = definitions.catalogue

    storage_goods =
      catalogue["goods"] |> Enum.sort() |> Enum.group_by(fn {_, item} -> item["hold"] end)

    storage =
      if draft["storage"] in ["dry", "reefer", "liquid"],
        do: draft["storage"],
        else: get_in(catalogue, ["goods", draft["good"], "hold"]) || "dry"

    choices = Map.get(storage_goods, storage, [])

    good =
      if storage == "liquid" do
        if Enum.any?(choices, &(elem(&1, 0) == draft["good"])),
          do: draft["good"],
          else: choices |> hd() |> elem(0)
      end

    blocks = draft["blocks"] || 1
    days = draft["days"] || 1
    used = Map.get(view.public["warehouse_utilization"] || %{}, port <> "|" <> (storage || ""), 0)
    company = view.private && view.private["company"]

    cash =
      if company && company["unpaid"] == 0 && is_nil(company["bankruptcy_ms"]),
        do: max(0, company["cash"] - company["reserved"]),
        else: 0

    leases =
      ((view.private && view.private["warehouses"]) || %{})
      |> Map.values()
      |> Enum.filter(&(&1["port"] == port))
      |> Enum.sort_by(& &1["id"])

    reservation_rows = Map.values((view.private && view.private["warehouse_reservations"]) || %{})

    now = view.public["clock_ms"]
    handling = TijaraTides.Domain.PortCargoMarket.handling_rate(catalogue["ports"][port])
    docked = ship && ship["status"] == "docked" && ship["port"] == port

    leases =
      Enum.map(leases, fn row ->
        w = WarehouseWorld.snapshot(row)
        external = WarehouseWorld.shared_external_volume(leases, reservation_rows, w, now)
        volume = Warehouse.volume(w, catalogue)
        reserved_volume = WarehouseWorld.reserved_volume(reservation_rows, w, catalogue)
        reservations = WarehouseWorld.reservations(reservation_rows, w)
        claimed = %{w | reservations: reservations}
        ready = (docked && now >= w.protected_ms) and now < w.expires_ms + w.grace_ms

        goods =
          if ready,
            do:
              catalogue["goods"]
              |> Enum.filter(fn {_, item} ->
                Warehouse.compatible?(w, item) and CargoRules.compatible_cargo?(ship, item)
              end),
            else: []

        # The transfer command checks these same limits, so offers never exceed them.
        loaded = %{claimed | external_volume: external}
        storing = now < w.expires_ms && not w.award_grace

        transfers =
          Enum.map(goods, fn {id, item} ->
            terms = %{
              now: now,
              ship_id: ship["id"],
              aboard: Enum.sum(for b <- ship["cargo"], b["good"] == id, do: b["quantity"]),
              minimum: 0,
              hold_rate: CargoRules.hold_rate(ship, catalogue),
              hold_lots: WarehouseWorld.hold_lots(ship, item, catalogue),
              cash: cash,
              cleaning: WarehouseWorld.cleaning_cost(ship, item),
              handling: handling,
              catalogue: catalogue
            }

            limit = fn side ->
              Warehouse.transfer_limits(loaded, side, item, %{
                terms
                | cleaning: if(side == "collect", do: terms.cleaning, else: 0)
              })
              |> Map.values()
              |> Enum.min()
              |> min(CargoRules.max_lots())
            end

            %{
              good: id,
              stored:
                Enum.sum(
                  for b <- w.cargo,
                      b.good == id and (is_nil(b.expires_ms) or b.expires_ms > now),
                      do: b.quantity
                ),
              store: if(storing, do: limit.("store"), else: 0),
              collect: limit.("collect")
            }
          end)
          |> Enum.filter(&(&1.store > 0 or &1.collect > 0 or &1.stored > 0))

        %{
          row: row,
          freshness:
            for(
              {good, batches} <- Enum.group_by(row["cargo"], & &1["good"]),
              Enum.any?(batches, & &1["expires_ms"]),
              do: %{
                good: good,
                remaining_ms: max(0, Enum.min(Enum.map(batches, & &1["expires_ms"])) - now)
              }
            ),
          replacement_offers:
            if(
              w.award_grace && now >= w.expires_ms && now < w.expires_ms + w.grace_ms &&
                volume > 0,
              do:
                Enum.map(Warehouse.terms(), fn days ->
                  n = div(volume + Warehouse.block_litres() - 1, Warehouse.block_litres())

                  %{
                    days: days,
                    blocks: n,
                    price: Warehouse.quote(max(0, used - n), w.storage, n, days)
                  }
                end),
              else: []
            ),
          liquidation: get_in(view, [:private, "warehouse_liquidations", w.id]),
          grace_end_ms: w.expires_ms + w.grace_ms,
          surcharge_bps: w.surcharge_bps,
          volume: volume,
          transfers: transfers,
          reserved_volume: reserved_volume,
          reserved_stock:
            Map.new(
              Enum.uniq(Enum.map(w.cargo, & &1.good)),
              &{&1, Warehouse.reserved_quantity(claimed, "stock", &1)}
            ),
          reservations:
            Enum.map(reservations, fn r ->
              %{
                id: r.id,
                kind: r.kind,
                good: r.good,
                quantity: r.quantity,
                ship: get_in(view.private, ["ships", r.ship_id, "name"]) || r.ship_id,
                auction: r.auction_id != nil or r.bid_id != nil
              }
            end),
          extension_open: Warehouse.extension_open?(w, now),
          extension_rate:
            Warehouse.extension_rate(
              w,
              Map.get(view.public["warehouse_utilization"] || %{}, w.port <> "|" <> w.storage, 0)
            ),
          renewal_open: Warehouse.renewal_open?(w, now),
          renewal_rate: w.renewal_rate,
          reservation_options:
            if(ship && now < w.expires_ms && now >= w.protected_ms,
              do:
                for(
                  {id, item} <- Enum.sort(catalogue["goods"]),
                  Warehouse.compatible?(w, item) and CargoRules.compatible_class?(ship, item),
                  kind <- ["stock", "capacity"],
                  not w.award_grace or kind == "stock",
                  n =
                    Warehouse.reservation_limit(
                      %{claimed | external_volume: external},
                      kind,
                      item,
                      now,
                      catalogue
                    ),
                  n > 0,
                  do: %{good: id, kind: kind, max: min(CargoRules.max_lots(), n)}
                ),
              else: []
            ),
          collection_stops:
            if(ship,
              do:
                Enum.filter(
                  Map.values(view.private["route_stops"] || %{}),
                  &(&1["ship_id"] == ship["id"] and &1["port"] == port)
                ),
              else: []
            ),
          free_blocks:
            if(not w.award_grace and now >= w.protected_ms and is_nil(w.next_days),
              do:
                w.blocks -
                  div(
                    volume + external + reserved_volume + Warehouse.block_litres() - 1,
                    Warehouse.block_litres()
                  ),
              else: 0
            )
        }
      end)

    %{
      good: good,
      blocks: blocks,
      days: days,
      used: used,
      pool: Warehouse.pool(storage),
      terms: Warehouse.terms(),
      storage: storage,
      storage_goods: storage_goods,
      price: Warehouse.quote(used, storage, blocks, days),
      leases: leases,
      cash: cash
    }
  end
end
