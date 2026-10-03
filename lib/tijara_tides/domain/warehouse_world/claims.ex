defmodule TijaraTides.Domain.WarehouseWorld.Claims do
  @moduledoc """
  Stock and receiving-space claims held against a lease. This module owns the
  reservation rows and their rules; `WarehouseWorld` loads leases and passes them in,
  so claims never call back into the lease root.
  """
  import TijaraTides.Domain.State
  alias TijaraTides.Domain.{CargoRules, Notices, Warehouse}
  alias TijaraTides.Domain.Warehouse.{Claim, Reservation, ReservationRows, Transition}

  @max_lots CargoRules.max_lots()

  @doc "Every claim row, for footprint calculations that span leases."
  def all(state), do: Map.values(entities(state, "warehouse_reservations"))

  def reservations(state, w) when is_map(state),
    do:
      with_auction_expiry(
        state,
        reservations(owned(state, "warehouse_reservations", "company_id", w.company_id), w)
      )

  def reservations(rows, w) when is_list(rows) do
    rows
    |> Enum.filter(&(&1["warehouse_id"] == w.id))
    |> Enum.map(&ReservationRows.decode/1)
    |> Enum.sort_by(&{&1.created_ms, &1.id})
  end

  @doc "Attach each auction claim's expiry, derived from the auction's immutable terms."
  def with_auction_expiry(state, reservations),
    do:
      Enum.map(reservations, fn r ->
        auction = r.auction_id && get(state, "auctions", r.auction_id)
        %{r | expires_ms: if(auction, do: auction["expires_ms"])}
      end)

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

  @doc "Write a pure warehouse transition's claim puts and deletes."
  def store(state, %Transition{} = transition) do
    state = Enum.reduce(transition.delete, state, &delete(&2, "warehouse_reservations", &1))

    Enum.reduce(transition.put, state, fn r, s ->
      put(s, "warehouse_reservations", r.id, ReservationRows.encode(r))
    end)
  end

  def reserve(state, w, account, cmd, id, catalogue) do
    with %Warehouse{company_id: owner} <- w,
         true <- owner == account["company_id"],
         %{"company_id" => ^owner} = ship <- get(state, "ships", cmd["ship"]),
         %{} = item <- catalogue["goods"][cmd["good"]],
         n when is_integer(n) and n > 0 and n <= @max_lots <- cmd["quantity"],
         kind when kind in ["stock", "capacity"] <- cmd["kind"] do
      stop_id = if cmd["stop_id"] not in [nil, ""], do: cmd["stop_id"]
      stop = stop_id && get(state, "route_stops", stop_id)

      cond do
        get(state, "companies", owner)["bankruptcy_ms"] != nil ->
          {:error, :finance_no_company}

        state.clock_ms >= w.expires_ms ->
          {:error, :warehouse_expired}

        state.clock_ms < w.protected_ms ->
          {:error, :warehouse_handling}

        not Warehouse.compatible?(w, item) or not CargoRules.compatible_class?(ship, item) ->
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
            {:ok, transition} -> {:ok, store(state, transition), %{}}
            error -> error
          end
      end
    else
      _ -> {:error, :warehouse_invalid}
    end
  end

  def cancel(state, account, id) do
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

  @doc "Earmark a committed remote fill; its incoming capacity has already been consumed."
  def earmark_remote_fill(state, w, link, order, quantity, catalogue) do
    id = "linked:" <> link["order_id"]
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
    store(state, Warehouse.earmark_fill(w, r, state.clock_ms, catalogue))
  end

  def release_link_stock(state, ship, stop, good, keep \\ 0) do
    claims =
      all(state)
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

  def consume(state, w, ship_id, good, kind, quantity),
    do: store(state, Warehouse.consume_reservations(w, ship_id, good, kind, quantity))

  def clear(state, w),
    do: store(state, Warehouse.clear_reservations(%{w | reservations: reservations(state, w)}))

  @doc """
  Only time ends a claim here: receiving space ends with the lease, and stock
  claims shrink to the stock that is still fresh. Ownership, stops, orders,
  bids and receivership release their claims in their own transitions.
  """
  def prune(state, w) do
    valid_ids =
      for r <- reservations(state, w),
          r.kind == "stock" or state.clock_ms < w.expires_ms,
          into: MapSet.new(),
          do: r.id

    transition =
      Warehouse.prune_reservations(
        %{w | reservations: reservations(state, w)},
        state.clock_ms,
        valid_ids
      )

    state
    |> store(transition)
    |> notify_released(w, Enum.map(transition.put, & &1.id) ++ transition.delete)
  end

  @doc "Release the claims on these loaded leases that a transition invalidated."
  def release_where(state, leases, released?) do
    Enum.reduce(leases, state, fn w, s ->
      case for(r <- w.reservations, released?.(r), do: r.id) do
        [] ->
          s

        ids ->
          s
          |> store(Warehouse.release_reservations(w, ids))
          |> notify_released(w, Enum.reject(ids, &String.starts_with?(&1, "linked:")))
      end
    end)
  end

  def back_order(state, w, %Claim{} = order, catalogue) do
    case Warehouse.back_order(w, order, state.clock_ms, catalogue) do
      {:ok, transition} -> {:ok, store(state, transition)}
      error -> error
    end
  end

  def release_trade(state, %Claim{} = order),
    do: delete(state, "warehouse_reservations", Claim.reservation_id(order))

  @doc "Liquidation ends the owner's collection claims; auction lots keep theirs."
  def release_collection(state, w) do
    reservations(state, w)
    |> Enum.filter(&(&1.auction_id == nil))
    |> Enum.reduce(state, fn r, s ->
      s
      |> delete("warehouse_reservations", r.id)
      |> Notices.notice(
        get(s, "companies", w.company_id)["account_id"],
        "reservation:" <> r.id,
        {"warehouse.reservation_released", %{"port" => w.port}}
      )
    end)
  end

  @doc "Replacement storage takes over the claims of the lease it replaces."
  def relocate(state, old, new) do
    Enum.reduce(entities(state, "warehouse_reservations"), state, fn {id, row}, s ->
      if row["warehouse_id"] == old,
        do: put(s, "warehouse_reservations", id, %{row | "warehouse_id" => new}),
        else: s
    end)
  end

  defp notify_released(state, w, ids) do
    account = get(state, "companies", w.company_id)["account_id"]

    Enum.reduce(ids, state, fn id, s ->
      Notices.notice(
        s,
        account,
        "reservation:" <> id,
        {"warehouse.reservation_released", %{"port" => w.port}}
      )
    end)
  end
end
