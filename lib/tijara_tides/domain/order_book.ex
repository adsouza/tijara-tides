defmodule TijaraTides.Domain.OrderBook do
  @moduledoc "Standing standardized-cargo orders, price-time priority and bounded public trade history."

  @fields ~w(id company_id warehouse_id port good side quantity price priority_ms priority_seq expires_ms)a
  @enforce_keys @fields
  @defaults [
    min_grade: 0,
    min_remaining_ms: 0,
    initial_price: nil,
    markdowns: nil,
    price_floor: 0,
    portions: %{}
  ]
  defstruct @fields ++ @defaults ++ [portion_id: nil, actual_grade: nil, lot_ids: nil]

  def supported?(item),
    do:
      is_map(item) and
        item["category"] in ["Bulk commodities", "Mass consumer products", "Scrap", "Perishables"]

  def grades, do: ["clearance", "fair", "good", "fresh"]

  def grade(batch, now) do
    fraction = TijaraTides.Domain.CargoFreshness.fraction(batch, now, nil)

    cond do
      fraction >= 7500 -> 3
      fraction >= 5000 -> 2
      fraction >= 2500 -> 1
      true -> 0
    end
  end

  def grade_row(row, now),
    do: grade(%{freshness: row["freshness"], expires_ms: row["expires_ms"]}, now)

  def schedule?(nil), do: true

  def schedule?(schedule) when is_map(schedule),
    do:
      Enum.sort(Map.keys(schedule)) == Enum.sort(grades()) and
        Enum.all?(Map.values(schedule), &(is_integer(&1) and &1 in 0..100))

  def schedule?(_), do: false

  def eligibility?(grade, life),
    do:
      is_integer(grade) and grade in 0..3 and TijaraTides.Domain.CargoRules.valid_remaining?(life)

  def eligible?(batch, now, policy) do
    grade(batch, now) >= (policy[:min_grade] || 0) and
      TijaraTides.Domain.CargoRules.qualifies_batch?(
        batch,
        now,
        policy[:min_remaining_ms] || 0,
        policy[:receiving_bps] || 10_000
      )
  end

  @doc "Select the same eligible physical lots for both matching and settlement."
  def sale_allocation(%__MODULE__{side: "sell"} = sell, batches, now, policy) do
    batches =
      Enum.filter(batches, fn b ->
        b.good == sell.good and (sell.lot_ids == nil or b.lot_id in sell.lot_ids) and
          eligible?(b, now, policy)
      end)

    {%{claim(sell) | lot_ids: Enum.map(batches, & &1.lot_id)},
     Enum.sum(Enum.map(batches, & &1.quantity))}
  end

  def effective_price(o, grade) do
    if o.markdowns,
      do:
        max(
          max(1, o.price_floor),
          div((o.initial_price || o.price) * o.markdowns[Enum.at(grades(), grade)] + 99, 100)
        ),
      else: o.price
  end

  def quotes(%__MODULE__{portions: portions, side: "sell"} = o) when map_size(portions) > 0 do
    Enum.map(portions, fn {id, p} ->
      %{
        o
        | portion_id: id,
          actual_grade: p["grade"],
          lot_ids: [p["lot_id"]],
          quantity: p["quantity"],
          price: p["price"],
          priority_ms: p["priority_ms"],
          priority_seq: p["priority_seq"]
      }
    end)
    |> Enum.sort_by(&{&1.price, priority(&1), &1.portion_id})
  end

  def quotes(o), do: [o]

  @doc "Accept a new order without overwriting an existing order's priority or terms."
  def accept(%__MODULE__{} = order, clock_ms, revision, id_taken?) do
    unless not id_taken? and order.side in ["buy", "sell"] and
             order.priority_ms == clock_ms and order.priority_seq == revision,
           do: raise(ArgumentError, "A new order requires a unique ID, side and current priority")

    terms!(order.quantity, order.price, order.expires_ms, clock_ms)

    unless eligibility?(order.min_grade, order.min_remaining_ms) and schedule?(order.markdowns) and
             is_integer(order.price_floor) and order.price_floor >= 0,
           do: raise(ArgumentError, "Invalid freshness terms")

    order
  end

  def amend(%__MODULE__{} = o, quantity, price, expires_ms, clock_ms, revision) do
    terms!(quantity, price, expires_ms, clock_ms)
    reset = quantity > o.quantity or price != o.price

    %{
      o
      | quantity: quantity,
        price: price,
        expires_ms: expires_ms,
        priority_ms: if(reset, do: clock_ms, else: o.priority_ms),
        priority_seq: if(reset, do: revision, else: o.priority_seq)
    }
  end

  def fill(%__MODULE__{} = current, %__MODULE__{} = o, n) do
    unless (current == o or (o.portion_id != nil and o in quotes(current))) and is_integer(n) and
             n > 0 and n <= o.quantity,
           do:
             raise(
               ArgumentError,
               "A fill requires a current order and a positive quantity within its remainder"
             )

    if n == current.quantity do
      :filled
    else
      portions =
        if o.portion_id do
          if n == o.quantity,
            do: Map.delete(current.portions, o.portion_id),
            else:
              Map.update!(
                current.portions,
                o.portion_id,
                &%{&1 | "quantity" => &1["quantity"] - n}
              )
        else
          current.portions
        end

      %{current | quantity: current.quantity - n, portions: portions}
    end
  end

  defp terms!(quantity, price, expiry, clock) do
    unless is_integer(quantity) and quantity in 1..TijaraTides.Domain.CargoRules.max_lots() and
             is_integer(price) and price in 1..1_000_000_000_000 and
             (is_nil(expiry) or
                (is_integer(expiry) and expiry > clock and expiry <= 9_000_000_000_000_000)),
           do:
             raise(
               ArgumentError,
               "Order terms require a bounded quantity, price and future expiry"
             )
  end

  def priority(o), do: {o.priority_ms, o.priority_seq, o.id}

  def claim(%__MODULE__{} = o),
    do:
      TijaraTides.Domain.Warehouse.Claim.new(
        id: o.id,
        kind: :order,
        company_id: o.company_id,
        warehouse_id: o.warehouse_id,
        good: o.good,
        quantity: o.quantity,
        side: o.side,
        lot_ids: o.lot_ids,
        created_ms: o.priority_ms
      )

  def counterparts(candidates, %__MODULE__{} = incoming) do
    candidates
    |> Enum.filter(
      &(&1.port == incoming.port and &1.good == incoming.good and &1.side != incoming.side and
          &1.company_id != incoming.company_id)
    )
    |> Enum.filter(fn candidate ->
      {buy, sell} =
        if incoming.side == "buy", do: {incoming, candidate}, else: {candidate, incoming}

      sell.actual_grade == nil or sell.actual_grade >= buy.min_grade
    end)
    |> Enum.filter(
      &if incoming.side == "buy", do: &1.price <= incoming.price, else: &1.price >= incoming.price
    )
    |> Enum.sort_by(&{if(incoming.side == "buy", do: &1.price, else: -&1.price), priority(&1)})
  end
end
