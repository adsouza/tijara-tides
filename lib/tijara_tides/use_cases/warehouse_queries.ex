defmodule TijaraTides.UseCases.WarehouseQueries do
  @moduledoc "Warehouse lease and transfer options from authorized read models."
  alias TijaraTides.Domain.{Fleet, CargoRules, Warehouse}

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
    space = docked && Fleet.capacity(ship, catalogue)
    class = docked && definitions.classes[ship["class"]]

    leases =
      Enum.map(leases, fn row ->
        w = Warehouse.from_row(row)
        volume = Warehouse.volume(w, catalogue)
        reserved_volume = Warehouse.reserved_volume(reservation_rows, w, catalogue)
        reservations = Warehouse.reservations(reservation_rows, w)
        ready = docked && now >= w.protected_ms

        goods =
          if ready,
            do:
              catalogue["goods"]
              |> Enum.filter(fn {_, item} ->
                Warehouse.compatible?(w, item) and CargoRules.compatible_cargo?(ship, item)
              end),
            else: []

        transfers =
          Enum.map(goods, fn {id, item} ->
            aboard = Enum.sum(for b <- ship["cargo"], b["good"] == id, do: b["quantity"])

            stored =
              Enum.sum(
                for b <- w.cargo,
                    b.good == id and (is_nil(b.expires_ms) or b.expires_ms > now),
                    do: b.quantity
              )

            store =
              if now < w.expires_ms,
                do:
                  min(
                    aboard,
                    div(
                      w.blocks * Warehouse.block_litres() - volume -
                        Warehouse.reserved_volume(reservation_rows, w, catalogue, ship["id"], id),
                      item["volume_l"]
                    )
                  ),
                else: 0

            collect =
              min(
                max(
                  0,
                  stored -
                    Warehouse.reserved_quantity(reservation_rows, w, "stock", id, ship["id"])
                ),
                min(
                  div(class["weight"] - space.weight, item["weight_kg"]),
                  div(class["volume"] - space.volume, item["volume_l"])
                )
              )

            %{
              good: id,
              stored: stored,
              store: max(0, min(CargoRules.max_lots(), min(store, div(cash, max(1, handling))))),
              collect:
                max(
                  0,
                  min(
                    min(CargoRules.max_lots(), collect),
                    div(max(0, cash - Warehouse.cleaning_cost(ship, item)), max(1, handling))
                  )
                )
            }
          end)
          |> Enum.filter(&(&1.store > 0 or &1.collect > 0 or &1.stored > 0))

        %{
          row: row,
          volume: volume,
          transfers: transfers,
          reserved_volume: reserved_volume,
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
          renewal_open: Warehouse.renewal_open?(w, now),
          renewal_rate: w.renewal_rate,
          reservation_options:
            if(ship && now < w.expires_ms && now >= w.protected_ms,
              do:
                for(
                  {id, item} <- Enum.sort(catalogue["goods"]),
                  Warehouse.compatible?(w, item) and CargoRules.compatible_class?(ship, item),
                  kind <- ["stock", "capacity"],
                  n =
                    if(kind == "stock",
                      do:
                        max(
                          0,
                          Enum.sum(
                            for b <- w.cargo,
                                b.good == id and (is_nil(b.expires_ms) or b.expires_ms > now),
                                do: b.quantity
                          ) - Warehouse.reserved_quantity(reservation_rows, w, "stock", id)
                        ),
                      else:
                        max(
                          0,
                          div(
                            w.blocks * Warehouse.block_litres() - volume - reserved_volume,
                            item["volume_l"]
                          )
                        )
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
            if(now >= w.protected_ms and is_nil(w.next_days),
              do:
                w.blocks -
                  div(
                    volume + reserved_volume + Warehouse.block_litres() - 1,
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
