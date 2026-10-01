defmodule TijaraTides.Domain.LiquidationPool do
  @moduledoc "Pure liquidation pool lifecycle and economic rules."
  @fields ~w(id company_id port status expires_ms grace_end_ms last_ms original_blocks occupied_blocks rent duration_ms surcharge_bps window_ms clearance_bps handling_rate rent_due rent_remainder handling_due clearance_remainders proceeds charged paid sunk completed_ms replacement_paid)a
  @enforce_keys @fields
  defstruct @fields

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

  def new(w, occupied, handling_rate) do
    %__MODULE__{
      id: w.id,
      company_id: w.company_id,
      port: w.port,
      status: "grace",
      expires_ms: w.expires_ms,
      grace_end_ms: w.expires_ms + w.grace_ms,
      last_ms: w.expires_ms,
      original_blocks: w.grace_blocks || w.blocks,
      occupied_blocks: occupied,
      rent: w.grace_rent || w.rent,
      duration_ms: w.grace_duration_ms || w.expires_ms - w.started_ms,
      surcharge_bps: w.surcharge_bps,
      window_ms: w.window_ms,
      clearance_bps: w.clearance_bps,
      handling_rate: handling_rate,
      rent_due: 0,
      rent_remainder: 0,
      handling_due: 0,
      clearance_remainders: %{},
      proceeds: 0,
      charged: 0,
      paid: 0,
      sunk: 0,
      completed_ms: nil,
      replacement_paid: 0
    }
  end

  def active?(%__MODULE__{status: status}), do: status != "completed"
  def active?(nil), do: false

  def accrue(%__MODULE__{status: "completed"} = p, _now), do: p

  def accrue(%__MODULE__{} = p, now) do
    grace = max(0, min(now, p.grace_end_ms) - p.last_ms)
    liquidating = max(0, now - max(p.last_ms, p.grace_end_ms))
    denominator = p.duration_ms * p.original_blocks * 10_000

    numerator =
      p.rent_remainder +
        p.rent * p.occupied_blocks *
          (grace * 10_000 + liquidating * (10_000 + p.surcharge_bps))

    %{
      p
      | rent_due: p.rent_due + div(numerator, denominator),
        rent_remainder: rem(numerator, denominator),
        last_ms: now
    }
  end

  def occupancy(%__MODULE__{} = p, blocks) do
    unless p.status != "completed" and is_integer(blocks) and blocks >= 0 and
             blocks <= p.occupied_blocks,
           do: raise(ArgumentError, "Liquidation occupancy cannot grow")

    %{p | occupied_blocks: blocks}
  end

  def clearance_value(%__MODULE__{} = p, good, numerator, denominator) do
    previous = Map.get(p.clearance_remainders, good, %{"numerator" => 0, "denominator" => 1})

    common =
      div(denominator, Integer.gcd(denominator, previous["denominator"])) *
        previous["denominator"]

    numerator =
      numerator * div(common, denominator) +
        previous["numerator"] * div(common, previous["denominator"])

    remaining = rem(numerator, common)
    divisor = Integer.gcd(remaining, common)

    remainder =
      Map.put(p.clearance_remainders, good, %{
        "numerator" => div(remaining, divisor),
        "denominator" => div(common, divisor)
      })

    {%{p | clearance_remainders: remainder}, div(numerator, common)}
  end

  def sale(%__MODULE__{} = p, proceeds, handling) do
    unless p.status == "liquidating" and proceeds >= 0 and handling >= 0,
      do: raise(ArgumentError, "Sale requires a live liquidation pool")

    %{
      p
      | proceeds: p.proceeds + proceeds,
        handling_due: p.handling_due + handling
    }
  end

  def begin(%__MODULE__{} = p, now) do
    unless p.status in ["grace", "liquidating"] and now >= p.grace_end_ms,
      do: raise(ArgumentError, "Liquidation starts only after its disclosed grace")

    %{p | status: "liquidating"}
  end

  def complete(%__MODULE__{} = p, charges, net, estate, now) do
    unless p.status == "liquidating" and charges + net == p.proceeds and net >= 0,
      do: raise(ArgumentError, "Invalid liquidation settlement")

    %{
      p
      | status: "completed",
        charged: charges,
        paid: if(estate, do: 0, else: net),
        sunk: if(estate, do: net, else: 0),
        completed_ms: now
    }
  end

  def replace(%__MODULE__{} = p, charges, now) do
    unless p.status == "grace" && p.proceeds == 0 &&
             charges == p.rent_due + p.handling_due,
           do: raise(ArgumentError, "Replacement requires the unchanged grace charges")

    %{
      p
      | status: "completed",
        completed_ms: now,
        replacement_paid: charges
    }
  end
end
