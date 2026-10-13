defmodule TijaraTides.Domain.Trade do
  @moduledoc "A manual trade intention; ownership, feasibility and prices are revalidated at execution."
  alias TijaraTides.Domain.Prices

  @enforce_keys [:side, :ship_id, :good, :quantity, :limit]
  defstruct [
    :side,
    :ship_id,
    :good,
    :quantity,
    :limit,
    :destination,
    :purchase_budget_id,
    :margin_bps,
    markdowns: nil,
    price_floor: 0,
    min_remaining_ms: 0,
    save_margin: false
  ]

  @type t :: %__MODULE__{
          side: String.t(),
          ship_id: String.t(),
          good: String.t(),
          quantity: integer(),
          limit: integer(),
          destination: String.t() | nil,
          margin_bps: 0..1_000 | nil,
          save_margin: boolean(),
          min_remaining_ms: non_neg_integer()
        }

  @max_margin_bps 1_000
  def max_margin_bps, do: @max_margin_bps

  @doc """
  The limit a queued trade waits with: a buy's ceiling raised, or a sell's floor
  lowered, by `margin_bps`. Rounds toward filling and never passes the price
  ceiling, so the result always fits the stored limit column.
  """
  def queued_limit("buy", limit, margin_bps),
    do: min(Prices.max_cents(), div(limit * (10_000 + margin_bps) + 9_999, 10_000))

  def queued_limit("sell", limit, margin_bps), do: div(limit * (10_000 - margin_bps), 10_000)
end
