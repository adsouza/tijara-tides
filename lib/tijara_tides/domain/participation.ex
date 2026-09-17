defmodule TijaraTides.Domain.Participation do
  @moduledoc "Company-capped economic participation, independent of login and fleet size."
  @default %{"decay_ms" => 604_800_000, "minimum_cents" => 10_000, "budget_quarters" => 1}
  @actions ~w(purchase sale exchange_purchase exchange_sale auction_purchase auction_sale auction_escrow departure warehouse_lease warehouse_renewal ship_purchase)
  def settings(catalogue) do
    settings = Map.merge(@default, catalogue["participation"] || %{})

    unless is_integer(settings["decay_ms"]) and settings["decay_ms"] > 0 and
             is_integer(settings["minimum_cents"]) and settings["minimum_cents"] > 0 and
             settings["budget_quarters"] in [1, 2],
           do: raise(ArgumentError, "Invalid participation settings")

    settings
  end

  def weight(nil, _now, _settings), do: 0

  def weight(last, now, settings) do
    decay = settings["decay_ms"]
    true = is_integer(decay) and decay > 0
    round(10_000 * :math.exp(-max(0, now - last) / decay))
  end

  def qualifies?(event, settings) do
    value =
      Enum.sum(
        for {account, amount} <- event.entries,
            account in ~w(inventory fleet prepaid_rent cash_reserved sales_revenue),
            amount > 0 or account == "sales_revenue",
            do: abs(amount)
      )

    event.kind in @actions and value >= settings["minimum_cents"]
  end

  def cycles(elapsed, scale, remainder) do
    credit = elapsed * scale + remainder
    {div(credit, 10_000), rem(credit, 10_000)}
  end
end
