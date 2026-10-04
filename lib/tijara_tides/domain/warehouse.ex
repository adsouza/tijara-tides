defmodule TijaraTides.Domain.Warehouse do
  @moduledoc "Typed storage, lease accounting and exclusive cargo claims."
  alias TijaraTides.Domain.Ship.CargoBatch
  alias __MODULE__.{Claim, Reservation, Transition}
  alias TijaraTides.Domain.CargoLots.Scope, as: Lots
  @day 86_400_000
  @terms [1, 3, 7]
  @storage_classes ["dry", "reefer", "liquid"]
  @fields ~w(id company_id port storage good blocks started_ms expires_ms rent prepaid protected_ms)a
  @renewal_defaults [
    source_lease_id: nil,
    space_group: nil,
    space_volumes: %{},
    award_id: nil,
    award_grace: false,
    grace_rent: nil,
    grace_blocks: nil,
    grace_duration_ms: nil,
    external_volume: 0,
    aging_bps: 2500,
    display_number: 1,
    renewal_rate: nil,
    next_rent: 0,
    next_days: nil,
    auto_days: nil,
    auto_cap: nil,
    grace_ms: 43_200_000,
    surcharge_bps: 2500,
    window_ms: 7_200_000,
    clearance_bps: 1000
  ]
  @enforce_keys @fields
  defstruct @fields ++ @renewal_defaults ++ [cargo: [], reservations: []]

  def block_litres, do: 100_000
  def terms, do: @terms
  def pool("dry"), do: %{blocks: 1000, rate: 100}
  def pool("reefer"), do: %{blocks: 250, rate: 300}
  def pool("liquid"), do: %{blocks: 500, rate: 200}
  def pool(_), do: nil

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

  def volume(w, catalogue),
    do: Enum.sum(for b <- w.cargo, do: b.quantity * catalogue["goods"][b.good]["volume_l"])

  def compatible?(w, item),
    do:
      (item["hold"] == w.storage or
         (w.storage in ["dry", "reefer"] and item["hold"] in ["dry", "reefer"])) and
        (w.storage != "liquid" or item["id"] == w.good)

  @doc "Choose qualifying earmarked stock first, then other available owned stock."
  def collection_source(warehouses, ship, good, clock, minimum, catalogue) do
    qualifying = fn w ->
      Enum.filter(w.cargo, fn b ->
        b.good == good and
          TijaraTides.Domain.CargoRules.qualifies_batch?(
            b,
            clock,
            minimum,
            TijaraTides.Domain.CargoRules.hold_rate(ship, catalogue)
          )
      end)
    end

    warehouses
    |> Enum.filter(fn w ->
      w.company_id == ship["company_id"] and w.port == ship["port"] and
        clock < w.expires_ms + w.grace_ms and
        Enum.sum(for b <- qualifying.(w), do: b.quantity) >
          reserved_quantity(w, "stock", good, ship["id"])
    end)
    |> Enum.sort_by(fn w ->
      own =
        Enum.any?(
          w.reservations,
          &(&1.kind == "stock" and &1.good == good and &1.ship_id == ship["id"])
        )

      expiry =
        qualifying.(w) |> Enum.map(&(&1.expires_ms || 9_223_372_036_854_775_807)) |> Enum.min()

      {if(own, do: 0, else: 1), expiry, w.id}
    end)
    |> List.first()
  end

  def receiving_open?(%__MODULE__{} = w, now), do: not w.award_grace and now < w.expires_ms

  def receiving_allowed?(%__MODULE__{} = w, company, port, item, now) when is_map(item),
    do:
      w.company_id == company and w.port == port and receiving_open?(w, now) and
        compatible?(w, item)

  def receiving_allowed?(%__MODULE__{}, _company, _port, _item, _now), do: false

  defdelegate cleaning_cost(last_liquid, item), to: TijaraTides.Domain.CargoRules

  def extension_open?(w, now),
    do: not w.award_grace and now < w.expires_ms and is_nil(w.next_days)

  def covered_until(w),
    do: w.expires_ms + (w.next_days || 0) * @day + if(w.award_grace, do: w.grace_ms, else: 0)

  @doc "Whether paid storage, clear of handling, lasts until `until_ms` (an auction close)."
  def covers?(%__MODULE__{} = w, until_ms, now),
    do: covered_until(w) >= until_ms and w.protected_ms <= now

  @doc "Fresh stock of `good` a new sell claim (exchange or auction) can still reserve."
  def claimable_stock(%__MODULE__{} = w, good, now),
    do: fresh_stock(w, good, now) - reserved_quantity(w, "stock", good)

  def day_ms, do: @day

  def extension_rate(w, used_blocks),
    do: w.renewal_rate || quote(max(0, used_blocks - w.blocks), w.storage, w.blocks, 1)

  def renewal_window_ms, do: 21_600_000

  def renewal_open?(w, now),
    do:
      not w.award_grace and now >= w.expires_ms - renewal_window_ms() and now < w.expires_ms and
        is_nil(w.next_days)

  defp fresh?(batch, clock), do: is_nil(batch.expires_ms) or batch.expires_ms > clock

  def fresh_stock(w, good, clock),
    do: Enum.sum(for b <- w.cargo, b.good == good, fresh?(b, clock), do: b.quantity)

  @doc "Most lots a new reservation of this kind may claim; reserve/4 and read models share it."
  def reservation_limit(%__MODULE__{} = w, "stock", item, now, _catalogue),
    do: max(0, fresh_stock(w, item["id"], now) - reserved_quantity(w, "stock", item["id"]))

  def reservation_limit(%__MODULE__{} = w, "capacity", item, _now, catalogue),
    do: free_lots(w, catalogue, reserved_volume(w, catalogue), item)

  @doc """
  Most lots one transfer may move under each limit. The transfer command rejects a
  larger quantity with the error for the limit it exceeds; read models offer the
  smallest. `terms` supplies the ship and company facts this model does not own.
  """
  def transfer_limits(%__MODULE__{} = w, "store", item, terms),
    do: %{
      stock: terms.aboard,
      space:
        free_lots(
          w,
          terms.catalogue,
          reserved_volume(w, terms.catalogue, terms.ship_id, item["id"]),
          item
        ),
      cash: div(max(0, terms.cash), max(1, terms.handling))
    }

  def transfer_limits(%__MODULE__{} = w, "collect", item, terms) do
    qualifying =
      Enum.sum(
        for b <- w.cargo,
            b.good == item["id"],
            TijaraTides.Domain.CargoRules.qualifies_batch?(
              b,
              terms.now,
              terms.minimum,
              terms.hold_rate
            ),
            do: b.quantity
      )

    %{
      stock: max(0, qualifying - reserved_quantity(w, "stock", item["id"], terms.ship_id)),
      hold: terms.hold_lots,
      cash: div(max(0, terms.cash - terms.cleaning), max(1, terms.handling))
    }
  end

  defp free_lots(w, catalogue, reserved, item),
    do:
      max(
        0,
        div(
          w.blocks * block_litres() - volume(w, catalogue) - w.external_volume - reserved,
          item["volume_l"]
        )
      )

  def accrue(%__MODULE__{award_grace: true} = w, _now), do: {w, 0}

  def accrue(%__MODULE__{} = w, now) do
    remaining =
      if w.expires_ms <= w.started_ms,
        do: 0,
        else: div(w.rent * max(0, w.expires_ms - now), w.expires_ms - w.started_ms)

    {%{w | prepaid: remaining}, w.prepaid - remaining}
  end

  def release_blocks(%__MODULE__{} = w, blocks, now, catalogue) do
    unless releasable?(w, blocks, now, catalogue),
      do: raise(ArgumentError, "Cannot release occupied or protected warehouse blocks")

    remaining_rent = div(w.rent * (w.blocks - blocks), w.blocks)

    remaining_prepaid =
      div(remaining_rent * max(0, w.expires_ms - now), max(1, w.expires_ms - w.started_ms))

    forfeited = w.prepaid - remaining_prepaid

    next = %{
      w
      | blocks: w.blocks - blocks,
        rent: remaining_rent,
        renewal_rate: if(w.renewal_rate, do: div(w.renewal_rate * (w.blocks - blocks), w.blocks)),
        prepaid: remaining_prepaid
    }

    {next, %{forfeited: forfeited, refund: div(forfeited, 2)}}
  end

  def lock_quote(%__MODULE__{} = w, now, used_blocks) do
    if is_nil(w.renewal_rate) and renewal_open?(w, now),
      do: %{w | renewal_rate: quote(max(0, used_blocks - w.blocks), w.storage, w.blocks, 1)},
      else: w
  end

  def pay_renewal(%__MODULE__{} = w, days, now, early \\ false) do
    unless days in @terms and if(early, do: extension_open?(w, now), else: renewal_open?(w, now)) and
             is_integer(w.renewal_rate),
           do: raise(ArgumentError, "Warehouse renewal is not open with a locked rate")

    %{w | next_rent: w.renewal_rate * days, next_days: days}
  end

  def renewal_settings(%__MODULE__{} = w, 0, _cap), do: %{w | auto_days: nil, auto_cap: nil}

  def renewal_settings(%__MODULE__{} = w, days, cap)
      when days in @terms and is_integer(cap) and cap >= 0,
      do: %{w | auto_days: days, auto_cap: cap}

  def roll_term(%__MODULE__{} = w, now, bankrupt) do
    if now >= w.expires_ms and w.next_days != nil and not bankrupt do
      {%{
         w
         | started_ms: w.expires_ms,
           expires_ms: w.expires_ms + w.next_days * @day,
           rent: w.next_rent,
           prepaid: w.next_rent,
           next_rent: 0,
           next_days: nil,
           renewal_rate: nil
       }, w.prepaid}
    else
      {w, 0}
    end
  end

  def spoil(%__MODULE__{} = w, now) do
    {expired, cargo} = Enum.split_with(w.cargo, &(not fresh?(&1, now)))
    {%{w | cargo: cargo}, Enum.sum(for b <- expired, do: b.quantity * b.unit_cost)}
  end

  @doc "Empty estate leases release after committed handling completes. Cargo sales belong to services."
  def clearance(%__MODULE__{} = w, now, bankrupt, _catalogue) do
    if bankrupt and now >= w.protected_ms and w.cargo == [] and w.reservations == [],
      do: %{cost: 0, value: 0, charges: 0}
  end

  def reserved_volume(%__MODULE__{} = w, catalogue, ship_id \\ nil, good \\ nil),
    do:
      Enum.sum(
        for r <- w.reservations,
            r.kind == "capacity",
            not (r.ship_id == ship_id and r.good == good),
            do: r.quantity * catalogue["goods"][r.good]["volume_l"]
      )

  def reserved_quantity(%__MODULE__{} = w, kind, good, except_ship \\ nil),
    do:
      Enum.sum(
        for r <- w.reservations,
            r.kind == kind and r.good == good and
              (is_nil(except_ship) or r.ship_id != except_ship),
            do: r.quantity
      )

  def consume_reservations(%__MODULE__{} = w, ship_id, good, kind, quantity) do
    {puts, deletes, _} =
      Enum.reduce(w.reservations, {[], [], quantity}, fn r, {puts, deletes, n} ->
        if r.ship_id == ship_id and r.good == good and r.kind == kind and n > 0 do
          taken = min(n, r.quantity)

          if taken == r.quantity,
            do: {puts, deletes ++ [r.id], n - taken},
            else: {puts ++ [%{r | quantity: r.quantity - taken}], deletes, n - taken}
        else
          {puts, deletes, n}
        end
      end)

    transition(w, puts, deletes)
  end

  def clear_reservations(%__MODULE__{} = w),
    do: transition(w, [], Enum.map(w.reservations, & &1.id))

  def release_reservations(%__MODULE__{} = w, ids) do
    held = MapSet.new(w.reservations, & &1.id)

    unless Enum.all?(ids, &MapSet.member?(held, &1)),
      do: raise(ArgumentError, "Released claims must belong to this warehouse")

    transition(w, [], ids)
  end

  def prune_reservations(%__MODULE__{} = w, now, valid_ids) do
    available =
      w.cargo
      |> Enum.filter(&fresh?(&1, now))
      |> Enum.group_by(& &1.good)
      |> Map.new(fn {g, bs} -> {g, Enum.sum(Enum.map(bs, & &1.quantity))} end)

    {puts, deletes, _} =
      Enum.reduce(w.reservations, {[], [], available}, fn r, {puts, deletes, stock} ->
        n =
          if MapSet.member?(valid_ids, r.id),
            do:
              if(r.kind == "stock",
                do: min(r.quantity, Map.get(stock, r.good, 0)),
                else: r.quantity
              ),
            else: 0

        {puts, deletes} =
          cond do
            n == 0 -> {puts, deletes ++ [r.id]}
            n < r.quantity -> {puts ++ [%{r | quantity: n}], deletes}
            true -> {puts, deletes}
          end

        {puts, deletes,
         if(r.kind == "stock", do: Map.update(stock, r.good, 0, &(&1 - n)), else: stock)}
      end)

    transition(w, puts, deletes)
  end

  def receive_cargo(%__MODULE__{} = w, cargo) do
    Enum.each(cargo, fn %CargoBatch{} = batch ->
      unless is_integer(batch.quantity) and batch.quantity > 0,
        do: raise(ArgumentError, "Warehouse cargo requires positive quantities")
    end)

    %{w | cargo: w.cargo ++ cargo}
  end

  def release_cargo(
        %Lots{} = lots,
        %__MODULE__{} = w,
        good,
        quantity,
        minimum \\ 0,
        receiving_bps \\ 10_000
      ) do
    {fresh, excluded} =
      Enum.split_with(
        w.cargo,
        &TijaraTides.Domain.CargoRules.qualifies_batch?(&1, lots.clock_ms, minimum, receiving_bps)
      )

    unless TijaraTides.Domain.CargoRules.valid_remaining?(minimum) and is_integer(quantity) and
             quantity > 0 and
             quantity <= Enum.sum(for b <- fresh, b.good == good, do: b.quantity),
           do: raise(ArgumentError, "Warehouse release exceeds fresh cargo")

    fresh = Enum.sort_by(fresh, &(&1.expires_ms || 9_223_372_036_854_775_807))
    {lots, cargo, remaining} = CargoBatch.take(lots, fresh, quantity, good)
    {lots, %{w | cargo: remaining ++ excluded}, cargo}
  end

  @doc "Read virtual batch allocations without allocating new lot identities."
  def cargo_allocations(w, good, now) do
    fresh =
      w.cargo
      |> Enum.filter(&(&1.good == good and fresh?(&1, now)))
      |> Enum.sort_by(&(&1.expires_ms || 9_223_372_036_854_775_807))

    w.reservations
    |> Enum.filter(&(&1.kind == "stock" and &1.good == good))
    |> Enum.sort_by(&{&1.created_ms, &1.id})
    |> Enum.reduce({%{}, fresh}, fn r, {held, free} ->
      {taken, free, _left} = virtual_take(free, r.quantity, r.expires_ms)
      {Map.put(held, r.id, taken), free}
    end)
  end

  def unreserved_cargo(w, good, now), do: cargo_allocations(w, good, now) |> elem(1)

  # Reservation grades are reconstructed from their auction's immutable expiry.
  # Quantity-only prefix skipping fails after a lower-grade auction is cancelled.
  defp virtual_take(batches, quantity, minimum_expiry) do
    Enum.reduce(batches, {[], [], quantity}, fn batch, {taken, free, left} ->
      eligible =
        minimum_expiry == nil or batch.expires_ms == nil or batch.expires_ms >= minimum_expiry

      n = if eligible, do: min(left, batch.quantity), else: 0
      taken = if n > 0, do: taken ++ [%{batch | quantity: n}], else: taken

      free =
        if n < batch.quantity, do: free ++ [%{batch | quantity: batch.quantity - n}], else: free

      {taken, free, left - n}
    end)
  end

  def release_claim_cargo(lots, w, claim, quantity) do
    allocated =
      cargo_allocations(w, claim.good, lots.clock_ms)
      |> elem(0)
      |> Map.get(Claim.reservation_id(claim), [])

    allocated =
      if claim.lot_ids, do: Enum.filter(allocated, &(&1.lot_id in claim.lot_ids)), else: allocated

    {lots, next, cargo} = release_allocation(lots, w, claim.good, quantity, allocated)

    {fresh, stale} =
      Enum.split_with(next.cargo, &(is_nil(&1.expires_ms) or &1.expires_ms > lots.clock_ms))

    {lots, %{next | cargo: fresh ++ stale}, cargo}
  end

  @doc "Release free batches while preserving all existing auction grades."
  def release_free_cargo(%Lots{} = lots, %__MODULE__{} = w, good, quantity, lot_ids \\ nil) do
    free = unreserved_cargo(w, good, lots.clock_ms)
    free = if lot_ids, do: Enum.filter(free, &(&1.lot_id in lot_ids)), else: free
    release_allocation(lots, w, good, quantity, free)
  end

  def release_liquidation_cargo(%Lots{} = lots, %__MODULE__{} = w, %Claim{} = claim, quantity) do
    {held, _free} = cargo_allocations(w, claim.good, lots.clock_ms)

    release_allocation(
      lots,
      w,
      claim.good,
      quantity,
      Map.get(held, Claim.reservation_id(claim), [])
    )
  end

  defp release_allocation(lots, w, good, quantity, allocated) do
    unless is_integer(quantity) and quantity > 0 and
             quantity <= Enum.sum(for b <- allocated, do: b.quantity),
           do: raise(ArgumentError, "Release exceeds its allocated fresh batches")

    {chosen, _, 0} = virtual_take(allocated, quantity, nil)
    quantities = Map.new(chosen, &{&1.lot_id, &1.quantity})

    {lots, cargo, remaining} =
      Enum.reduce(w.cargo, {lots, [], []}, fn batch, {lots, cargo, remaining} ->
        n = if batch.good == good, do: Map.get(quantities, batch.lot_id, 0), else: 0

        if n == 0 do
          {lots, cargo, remaining ++ [batch]}
        else
          {lots, part, rest} = CargoBatch.take(lots, [batch], n, good)
          {lots, cargo ++ part, remaining ++ rest}
        end
      end)

    {lots, %{w | cargo: remaining}, cargo}
  end

  def protect_handling(%__MODULE__{} = w, until_ms), do: %{w | protected_ms: until_ms}

  @doc "Back an exchange order with exclusive stock or receiving space."
  def back_order(%__MODULE__{} = w, %Claim{} = order, now, catalogue) do
    item = catalogue["goods"][order.good]

    cond do
      (order.side == "buy" and not receiving_open?(w, now)) or
          (now >= w.expires_ms and
             not (order.side == "sell" and
                      (order.liquidation or
                         ((order.kind == :order or w.award_grace) and
                            now < w.expires_ms + w.grace_ms)))) ->
        {:error, :warehouse_expired}

      not compatible?(w, item) ->
        {:error, :incompatible_cargo}

      order.side == "buy" and
          order.quantity > reservation_limit(w, "capacity", item, now, catalogue) ->
        {:error, :warehouse_capacity}

      order.side == "sell" and
          claimable_stock(w, order.good, now) < order.quantity ->
        {:error, :insufficient_cargo}

      true ->
        r = %Reservation{
          id: Claim.reservation_id(order),
          warehouse_id: w.id,
          company_id: w.company_id,
          ship_id: nil,
          order_id: if(Claim.owner(order, :order), do: order.id),
          auction_id: if(Claim.owner(order, :auction), do: order.id),
          bid_id: if(Claim.owner(order, :bid), do: order.id),
          good: order.good,
          kind: if(order.side == "buy", do: "capacity", else: "stock"),
          quantity: order.quantity,
          created_ms: order.created_ms || now,
          stop_id: nil,
          expires_ms: order.expires_ms
        }

        {:ok, transition(w, [r], [])}
    end
  end

  def order_backed?(%__MODULE__{} = w, %Claim{} = order, now) do
    r = Enum.find(w.reservations, &(&1.id == Claim.reservation_id(order)))

    (w.expires_ms > now or
       (order.side == "sell" and order.liquidation) or
       (order.side == "sell" and order.kind == :order and now < w.expires_ms + w.grace_ms) or
       (order.kind in [:auction, :bid] and covered_until(w) >= (order.closes_ms || now))) and
      not is_nil(r) and r.quantity >= order.quantity and
      (order.side != "sell" or
         if(order.liquidation,
           do:
             Enum.sum(
               for b <-
                     Map.get(
                       elem(cargo_allocations(w, order.good, now), 0),
                       Claim.reservation_id(order),
                       []
                     ),
                   do: b.quantity
             ) >= order.quantity,
           else: fresh_stock(w, order.good, now) >= order.quantity
         ))
  end

  def consume_order(%__MODULE__{} = w, %Claim{} = order, n) do
    r = Enum.find(w.reservations, &(&1.id == Claim.reservation_id(order)))

    unless r && is_integer(n) && n > 0 && n <= r.quantity,
      do: raise(ArgumentError, "Trade fill exceeds its warehouse reservation")

    if r.quantity == n,
      do: transition(w, [], [r.id]),
      else: transition(w, [%{r | quantity: r.quantity - n}], [])
  end

  defp transition(w, puts, deletes) do
    replaced = MapSet.new(deletes ++ Enum.map(puts, & &1.id))

    children =
      (Enum.reject(w.reservations, &MapSet.member?(replaced, &1.id)) ++ puts)
      |> Enum.sort_by(&{&1.created_ms, &1.id})

    %Transition{warehouse: %{w | reservations: children}, put: puts, delete: deletes}
  end

  def releasable?(%__MODULE__{} = w, blocks, now, catalogue),
    do:
      is_integer(blocks) and blocks > 0 and blocks <= w.blocks and now >= w.protected_ms and
        is_nil(w.next_days) and
        volume(w, catalogue) + w.external_volume + reserved_volume(w, catalogue) <=
          (w.blocks - blocks) * block_litres()

  @doc "A settled incoming fill converts its capacity backing into a ship stock claim."
  def earmark_fill(%__MODULE__{} = w, %Reservation{kind: "stock"} = r, now, catalogue) do
    unless r.quantity > 0 and r.company_id == w.company_id and r.ship_id != nil and
             now < w.expires_ms and compatible?(w, catalogue["goods"][r.good]) and
             r.quantity + reserved_quantity(w, "stock", r.good) <= fresh_stock(w, r.good, now),
           do: raise(ArgumentError, "Remote fill must be backed by available owned stock")

    transition(w, [r], [])
  end

  def reserve(%__MODULE__{} = w, %Reservation{} = r, now, catalogue) do
    item = catalogue["goods"][r.good]

    cond do
      now >= w.expires_ms or (w.award_grace and r.kind == "capacity") ->
        {:error, :warehouse_expired}

      now < w.protected_ms ->
        {:error, :warehouse_handling}

      not compatible?(w, item) ->
        {:error, :incompatible_cargo}

      length(w.reservations) >= 100 ->
        {:error, :warehouse_capacity}

      r.kind == "stock" and r.quantity > reservation_limit(w, "stock", item, now, catalogue) ->
        {:error, :insufficient_cargo}

      r.kind == "capacity" and
          r.quantity > reservation_limit(w, "capacity", item, now, catalogue) ->
        {:error, :warehouse_capacity}

      true ->
        {:ok, transition(w, [r], [])}
    end
  end
end
