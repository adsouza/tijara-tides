defmodule TijaraTides.Domain.WarehouseLiquidationWorld do
  @moduledoc "Durable expired-lease pools, exact accrued charges and terminal payouts."
  alias TijaraTides.Domain.{State, Warehouse}

  def terms(catalogue) do
    config = Map.get(catalogue, "warehouse_liquidation", %{})

    defaults = [
      grace_ms: 43_200_000,
      surcharge_bps: 2500,
      window_ms: 7_200_000,
      clearance_bps: 1000
    ]

    Map.new(defaults, fn {key, default} ->
      value = Map.get(config, Atom.to_string(key), default)
      true = is_integer(value) and value >= 0
      true = key not in [:grace_ms, :window_ms] or value > 0
      true = key != :clearance_bps or value <= 10_000
      {key, value}
    end)
  end

  def pool(state, id), do: State.get(state, "warehouse_liquidations", id)

  def active?(state, id),
    do: match?(%{"status" => status} when status != "completed", pool(state, id))

  def prepare(state, w, catalogue) do
    company = State.get(state, "companies", w.company_id)

    if state.clock_ms >= w.expires_ms and
         (company["bankruptcy_ms"] == nil or active?(state, w.id)) do
      state =
        if pool(state, w.id) do
          state
        else
          put(state, %{
            "id" => w.id,
            "company_id" => w.company_id,
            "port" => w.port,
            "status" => "grace",
            "expires_ms" => w.expires_ms,
            "grace_end_ms" => w.expires_ms + w.grace_ms,
            "last_ms" => w.expires_ms,
            "original_blocks" => w.grace_blocks || w.blocks,
            "occupied_blocks" => occupied(w, catalogue),
            "rent" => w.grace_rent || w.rent,
            "duration_ms" => w.grace_duration_ms || w.expires_ms - w.started_ms,
            "surcharge_bps" => w.surcharge_bps,
            "window_ms" => w.window_ms,
            "clearance_bps" => w.clearance_bps,
            "handling_rate" =>
              TijaraTides.Domain.PortCargoMarket.handling_rate(catalogue["ports"][w.port]),
            "rent_due" => 0,
            "rent_remainder" => 0,
            "handling_due" => 0,
            "clearance_remainders" => %{},
            "proceeds" => 0,
            "charged" => 0,
            "paid" => 0,
            "sunk" => 0,
            "completed_ms" => nil,
            "replacement_paid" => 0
          })
        end

      before_remove(state, w.id)
    else
      state
    end
  end

  # Carry the rational remainder across ticks and across the grace boundary. Rounding
  # once per tick would otherwise make rent depend on the coordinator's tick size.
  def before_remove(state, id) do
    case pool(state, id) do
      %{"status" => status} = p when status != "completed" ->
        now = state.clock_ms
        grace = max(0, min(now, p["grace_end_ms"]) - p["last_ms"])
        liquidating = max(0, now - max(p["last_ms"], p["grace_end_ms"]))
        denominator = p["duration_ms"] * p["original_blocks"] * 10_000

        numerator =
          p["rent_remainder"] +
            p["rent"] * p["occupied_blocks"] *
              (grace * 10_000 + liquidating * (10_000 + p["surcharge_bps"]))

        put(state, %{
          p
          | "rent_due" => p["rent_due"] + div(numerator, denominator),
            "rent_remainder" => rem(numerator, denominator),
            "last_ms" => now
        })

      _ ->
        state
    end
  end

  def occupancy(state, id, blocks) do
    p = pool(state, id)

    unless p["status"] != "completed" and is_integer(blocks) and blocks >= 0 and
             blocks <= p["occupied_blocks"],
           do: raise(ArgumentError, "Liquidation occupancy cannot grow")

    put(state, %{p | "occupied_blocks" => blocks})
  end

  def clearance_value(state, id, good, numerator, denominator) do
    p = pool(state, id)
    previous = Map.get(p["clearance_remainders"], good, %{"numerator" => 0, "denominator" => 1})

    common =
      div(denominator, Integer.gcd(denominator, previous["denominator"])) *
        previous["denominator"]

    numerator =
      numerator * div(common, denominator) +
        previous["numerator"] * div(common, previous["denominator"])

    remaining = rem(numerator, common)
    divisor = Integer.gcd(remaining, common)

    remainder =
      Map.put(p["clearance_remainders"], good, %{
        "numerator" => div(remaining, divisor),
        "denominator" => div(common, divisor)
      })

    {put(state, %{p | "clearance_remainders" => remainder}), div(numerator, common)}
  end

  def sale(state, id, proceeds, handling) do
    p = pool(state, id)

    unless p["status"] == "liquidating" and proceeds >= 0 and handling >= 0,
      do: raise(ArgumentError, "Sale requires a live liquidation pool")

    put(state, %{
      p
      | "proceeds" => p["proceeds"] + proceeds,
        "handling_due" => p["handling_due"] + handling
    })
  end

  def begin(state, id) do
    p = pool(state, id)

    unless p["status"] in ["grace", "liquidating"] and state.clock_ms >= p["grace_end_ms"],
      do: raise(ArgumentError, "Liquidation starts only after its disclosed grace")

    put(state, %{p | "status" => "liquidating"})
  end

  def complete(state, id, charges, net, estate) do
    p = pool(state, id)

    unless p["status"] == "liquidating" and charges + net == p["proceeds"] and net >= 0,
      do: raise(ArgumentError, "Invalid liquidation settlement")

    put(state, %{
      p
      | "status" => "completed",
        "charged" => charges,
        "paid" => if(estate, do: 0, else: net),
        "sunk" => if(estate, do: net, else: 0),
        "completed_ms" => state.clock_ms
    })
  end

  def replace(state, id, charges) do
    p = pool(state, id)

    unless p["status"] == "grace" && p["proceeds"] == 0 &&
             charges == p["rent_due"] + p["handling_due"],
           do: raise(ArgumentError, "Replacement requires the unchanged grace charges")

    put(state, %{
      p
      | "status" => "completed",
        "completed_ms" => state.clock_ms,
        "replacement_paid" => charges
    })
  end

  defp occupied(w, catalogue),
    do:
      div(Warehouse.volume(w, catalogue) + Warehouse.block_litres() - 1, Warehouse.block_litres())

  defp put(s, p), do: State.put(s, "warehouse_liquidations", p["id"], p)
end
