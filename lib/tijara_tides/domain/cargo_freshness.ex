defmodule TijaraTides.Domain.CargoFreshness do
  @moduledoc "Exact biological age with a projected expiry under current storage conditions."
  @ordinary 10_000
  def rate(storage, catalogue \\ %{}) do
    if storage == "reefer" do
      rate = get_in(catalogue, ["refrigeration", "aging_bps"]) || 2500
      true = is_integer(rate) and rate in 1..@ordinary
      rate
    else
      @ordinary
    end
  end

  def origin(batch),
    do: if(batch.freshness, do: batch.freshness["origin_expires_ms"], else: batch.expires_ms)

  def initialize(%{expires_ms: nil} = batch, _now, _item), do: batch
  def initialize(%{freshness: %{}} = batch, _now, _item), do: batch

  def initialize(batch, now, item) do
    shelf = if item, do: max(1, item["shelf_ms"]), else: max(1, batch.expires_ms - now)

    %{
      batch
      | freshness: %{
          "origin_expires_ms" => batch.expires_ms,
          "harvest_ms" => batch.expires_ms - shelf,
          "shelf_ms" => shelf,
          "at_ms" => now,
          "remaining_units" => max(0, batch.expires_ms - now) * @ordinary,
          "rate_bps" => @ordinary,
          "expires_ms" => batch.expires_ms
        }
    }
  end

  def remaining_units(batch, now) do
    f = batch.freshness
    max(0, f["remaining_units"] - max(0, now - f["at_ms"]) * f["rate_bps"])
  end

  def recondition(batch, now, rate, item \\ nil)
  def recondition(%{expires_ms: nil} = batch, _now, _rate, _item), do: batch

  def recondition(batch, now, rate, item) do
    true = is_integer(rate) and rate in 1..@ordinary
    batch = initialize(batch, now, item)
    true = now >= batch.freshness["at_ms"]
    units = remaining_units(batch, now)
    expiry = now + div(units + rate - 1, rate)

    %{
      batch
      | expires_ms: expiry,
        freshness: %{
          batch.freshness
          | "at_ms" => now,
            "remaining_units" => units,
            "rate_bps" => rate,
            "expires_ms" => expiry
        }
    }
  end

  def ratio(batch, now, item) do
    batch = initialize(batch, now, item)

    if batch.expires_ms do
      total = max(1, batch.freshness["shelf_ms"] * @ordinary)
      {min(total, remaining_units(batch, now)), total}
    else
      {1, 1}
    end
  end

  def fraction(batch, now, item) do
    {numerator, denominator} = ratio(batch, now, item)
    div(numerator * @ordinary, denominator)
  end

  def valid?(%{freshness: nil}), do: true

  def valid?(batch) do
    f = batch.freshness

    is_map(f) and
      Enum.sort(Map.keys(f)) ==
        Enum.sort(
          ~w(origin_expires_ms harvest_ms shelf_ms at_ms remaining_units rate_bps expires_ms)
        ) and
      Enum.all?(Map.values(f), &is_integer/1) and f["shelf_ms"] > 0 and f["at_ms"] >= 0 and
      f["remaining_units"] >= 0 and f["rate_bps"] in 1..10_000 and
      f["origin_expires_ms"] == f["harvest_ms"] + f["shelf_ms"] and
      f["expires_ms"] == batch.expires_ms and
      if f["remaining_units"] == 0,
        do: f["expires_ms"] <= f["at_ms"],
        else:
          f["expires_ms"] ==
            f["at_ms"] + div(f["remaining_units"] + f["rate_bps"] - 1, f["rate_bps"])
  end

  def copy(source, target),
    do: %{target | expires_ms: source.expires_ms, freshness: source.freshness}
end
