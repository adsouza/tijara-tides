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

  # exp(-t/decay) = 2^(-t/half_life), evaluated as a 1/16-step table of 2^(-k/16) in
  # basis points with linear interpolation inside a step. Integer throughout, so the
  # world-wide scale reproduces across hosts and Erlang builds rather than tracking libm.
  @ln2_bps 6931
  @steps {10_000, 9576, 9170, 8781, 8409, 8052, 7711, 7384, 7071, 6771, 6484, 6208, 5946, 5693,
          5453, 5221, 5000}

  def weight(nil, _now, _settings), do: 0

  def weight(last, now, settings) do
    half = div(settings["decay_ms"] * @ln2_bps, 10_000)
    elapsed = max(0, now - last)
    halvings = div(elapsed, half)

    if halvings > 14 do
      0
    else
      offset = elapsed - halvings * half
      index = div(offset * 16, half)
      from = elem(@steps, index)
      into = elem(@steps, index + 1)

      div(
        from - div((from - into) * (offset * 16 - index * half), half),
        Integer.pow(2, halvings)
      )
    end
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
