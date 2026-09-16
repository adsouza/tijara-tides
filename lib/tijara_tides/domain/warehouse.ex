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
    display_number: 1,
    renewal_rate: nil,
    next_rent: 0,
    next_days: nil,
    auto_days: nil,
    auto_cap: nil
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
    do: item["hold"] == w.storage and (w.storage != "liquid" or item["id"] == w.good)

  def cleaning_cost(last_liquid, item) do
    if item["hold"] == "liquid" and last_liquid not in [nil, item["id"]],
      do: if("vegetable_oil" in [last_liquid, item["id"]], do: 25_000, else: 5000),
      else: 0
  end

  def extension_open?(w, now), do: now < w.expires_ms and is_nil(w.next_days)
  def covered_until(w), do: w.expires_ms + (w.next_days || 0) * @day
  def day_ms, do: @day

  def extension_rate(w, used_blocks),
    do: w.renewal_rate || quote(max(0, used_blocks - w.blocks), w.storage, w.blocks, 1)

  def renewal_window_ms, do: 21_600_000

  def renewal_open?(w, now),
    do: now >= w.expires_ms - renewal_window_ms() and now < w.expires_ms and is_nil(w.next_days)

  defp fresh?(batch, clock), do: is_nil(batch.expires_ms) or batch.expires_ms > clock

  defp fresh_stock(w, good, clock),
    do: Enum.sum(for b <- w.cargo, b.good == good, fresh?(b, clock), do: b.quantity)

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

  def clearance(%__MODULE__{} = w, now, bankrupt, catalogue) do
    if now >= w.protected_ms and
         ((bankrupt and w.cargo == [] and w.reservations == []) or
            (not bankrupt and now >= w.expires_ms + div(@day, 2))) do
      cost = Enum.sum(for b <- w.cargo, do: b.quantity * b.unit_cost)

      value =
        Enum.sum(
          for b <- w.cargo,
              do:
                b.quantity *
                  min(b.unit_cost, div(catalogue["goods"][b.good]["reference_cents"], 2))
        )

      grace = div(w.rent * max(0, now - w.expires_ms), max(1, w.expires_ms - w.started_ms))
      %{cost: cost, value: value, charges: min(value, grace)}
    end
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

  def release_cargo(%Lots{} = lots, %__MODULE__{} = w, good, quantity) do
    unless is_integer(quantity) and quantity > 0 and
             quantity <= fresh_stock(w, good, lots.clock_ms),
           do: raise(ArgumentError, "Warehouse release exceeds fresh cargo")

    {fresh, stale} = Enum.split_with(w.cargo, &fresh?(&1, lots.clock_ms))
    {lots, cargo, remaining} = CargoBatch.take(lots, fresh, quantity, good)
    {lots, %{w | cargo: remaining ++ stale}, cargo}
  end

  def protect_handling(%__MODULE__{} = w, until_ms), do: %{w | protected_ms: until_ms}

  @doc "Back an exchange order with exclusive stock or receiving space."
  def back_order(%__MODULE__{} = w, %Claim{} = order, now, catalogue) do
    item = catalogue["goods"][order.good]
    stock = fresh_stock(w, order.good, now)

    cond do
      now >= w.expires_ms ->
        {:error, :warehouse_expired}

      not compatible?(w, item) ->
        {:error, :incompatible_cargo}

      order.side == "buy" and
          volume(w, catalogue) + reserved_volume(w, catalogue) +
            order.quantity * item["volume_l"] > w.blocks * block_litres() ->
        {:error, :warehouse_capacity}

      order.side == "sell" and
          stock - reserved_quantity(w, "stock", order.good) < order.quantity ->
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
          created_ms: now,
          stop_id: nil
        }

        {:ok, transition(w, [r], [])}
    end
  end

  def order_backed?(%__MODULE__{} = w, %Claim{} = order, now) do
    r = Enum.find(w.reservations, &(&1.id == Claim.reservation_id(order)))

    (w.expires_ms > now or
       (order.kind in [:auction, :bid] and covered_until(w) >= (order.closes_ms || now))) and
      not is_nil(r) and r.quantity >= order.quantity and
      (order.side != "sell" or fresh_stock(w, order.good, now) >= order.quantity)
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
        volume(w, catalogue) + reserved_volume(w, catalogue) <=
          (w.blocks - blocks) * block_litres()

  def reserve(%__MODULE__{} = w, %Reservation{} = r, now, catalogue) do
    item = catalogue["goods"][r.good]

    cond do
      now >= w.expires_ms ->
        {:error, :warehouse_expired}

      now < w.protected_ms ->
        {:error, :warehouse_handling}

      not compatible?(w, item) ->
        {:error, :incompatible_cargo}

      length(w.reservations) >= 100 ->
        {:error, :warehouse_capacity}

      r.kind == "stock" and
          r.quantity + reserved_quantity(w, r.kind, r.good) > fresh_stock(w, r.good, now) ->
        {:error, :insufficient_cargo}

      r.kind == "capacity" and
          volume(w, catalogue) + reserved_volume(w, catalogue) + r.quantity * item["volume_l"] >
            w.blocks * block_litres() ->
        {:error, :warehouse_capacity}

      true ->
        {:ok, transition(w, [r], [])}
    end
  end
end
