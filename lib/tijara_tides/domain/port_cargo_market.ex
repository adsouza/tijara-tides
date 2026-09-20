defmodule TijaraTides.Domain.PortCargoMarket do
  @moduledoc "Finite market quotes, catalogue rules, producer output, demand and buyer-budget recovery."
  alias TijaraTides.Domain.PortCargoMarket.Batch
  alias TijaraTides.Domain.PortCargoMarket.Lots
  alias TijaraTides.Domain.Ship.CargoBatch
  @market_replenishment_ms 150_000

  @fields ~w(port good merchant seller buyer stock demand budget batches last_production)a
  defstruct @fields ++ [feedstock: false, production_credit: 0, warehouse_active: false]

  def quote(%__MODULE__{} = market, catalogue) do
    item = catalogue["goods"][market.good]
    # Clustered ports take their ask and bid from RegionalPricing instead.
    ask_base = if market.merchant, do: 105, else: 90
    bid_base = if market.merchant, do: 95, else: 110

    %{
      "ask" => div(item["reference_cents"] * (ask_base + div(500 - market.stock, 25)), 100),
      "bid" => div(item["reference_cents"] * (bid_base - div(500 - market.demand, 25)), 100),
      "handling_fee" => handling_rate(catalogue["ports"][market.port]),
      "freshness_batches" => if(market.seller, do: market.batches, else: []),
      # Factory feedstock is physical inventory, not an offer to sell it.
      "stock" => if(market.seller, do: market.stock, else: 0),
      "demand" => if(market.buyer, do: market.demand, else: 0),
      "buyer_budget" => if(market.buyer, do: market.budget, else: 0),
      "manual" => item["manual"] and (not market.merchant or market.warehouse_active)
    }
  end

  @doc "Release supplier cargo, preserving perishable lot identities and split lineage."
  def supply(%Lots{} = lots, %__MODULE__{} = market, quantity, price, item) do
    unless item["id"] == market.good and market.seller and is_integer(quantity) and quantity > 0 and
             quantity <= market.stock and is_integer(price) and price >= 0,
           do: raise(ArgumentError, "Market cannot supply the requested cargo quantity or price")

    {lots, taken, remaining} =
      if item["shelf_ms"] > 0 or market.merchant do
        unless Enum.all?(
                 market.batches,
                 &(is_nil(&1.expires_ms) or &1.expires_ms > lots.clock_ms)
               ) and
                 Enum.sum(Enum.map(market.batches, & &1.quantity)) == market.stock,
               do: raise(ArgumentError, "Market freshness batches must match its unexpired stock")

        Lots.take(lots, market.batches, quantity, market.good)
      else
        {next, lot} = Lots.create(lots, market.good, quantity, nil)
        {next, [lot], []}
      end

    cargo =
      Enum.map(
        taken,
        &%CargoBatch{
          good: market.good,
          unit_cost: price,
          lot_id: &1.lot_id,
          quantity: &1.quantity,
          expires_ms: &1.expires_ms
        }
      )

    {lots,
     %{
       market
       | stock: market.stock - quantity,
         budget: market.budget + price * quantity,
         batches: remaining
     }, cargo}
  end

  @doc "Consume finite buyer demand and funds; only merchants retain purchased stock."
  def receive_cargo(%__MODULE__{} = market, quantity, price, cargo \\ nil) do
    unless market.buyer and is_integer(quantity) and quantity > 0 and quantity <= market.demand and
             is_integer(price) and price >= 0 and quantity * price <= market.budget and
             (not market.feedstock or market.stock + quantity <= 500),
           do: raise(ArgumentError, "Market cannot fund the requested cargo purchase")

    batches =
      if market.merchant do
        unless is_list(cargo) and Enum.sum(Enum.map(cargo, & &1.quantity)) == quantity and
                 Enum.all?(cargo, &(&1.good == market.good)),
               do: raise(ArgumentError, "Merchant purchases require the delivered cargo batches")

        market.batches ++
          Enum.map(
            cargo,
            &%Batch{
              lot_id: &1.lot_id,
              quantity: &1.quantity,
              expires_ms: &1.expires_ms
            }
          )
      else
        market.batches
      end

    %{
      market
      | demand: market.demand - quantity,
        budget: market.budget - quantity * price,
        batches: batches,
        stock: market.stock + if(market.merchant or market.feedstock, do: quantity, else: 0)
    }
  end

  def validate_catalogue!(catalogue) do
    Enum.each(catalogue["goods"], fn {id, item} ->
      unless Regex.match?(~r/^[a-z]+(_[a-z]+)*$/, id) and item["id"] == id and
               is_binary(item["name"]) and String.trim(item["name"]) != "",
             do: raise(ArgumentError, "cargo requires a machine ID and display name: #{id}")
    end)

    Enum.each(raw_goods(), fn good ->
      unless Map.has_key?(catalogue["goods"], good),
        do: raise(ArgumentError, "unknown raw production good: #{good}")
    end)

    TijaraTides.Domain.Manufacturing.validate!(catalogue)

    Enum.each(catalogue["ports"], fn {port, definition} ->
      Enum.each(definition["roles"], fn {good, _role} ->
        unless Map.has_key?(catalogue["goods"], good),
          do: raise(ArgumentError, "unknown role good at #{port}: #{good}")
      end)
    end)
  end

  def raw_goods,
    do: [
      "spices",
      "iron_ore",
      "grain",
      "lumber",
      "crude_oil",
      "fruit",
      "seafood",
      "meat",
      "aluminium_scrap",
      "copper_scrap",
      "recovered_plastics"
    ]

  def handling_rate(%{"tiers" => %{"cost" => "high"}}), do: 600
  def handling_rate(%{"tiers" => %{"cost" => "low"}}), do: 200
  def handling_rate(_), do: 400

  def initialize(%Lots{} = lots, port, good, role, item) do
    merchant = String.contains?(role, "/")
    seller = String.contains?(role, "exp")
    buyer = String.contains?(role, "imp")

    {lots, batches} =
      if item["shelf_ms"] > 0 and seller and not merchant do
        {next, lot} = Lots.create(lots, good, 500, lots.clock_ms + item["shelf_ms"])
        {next, [lot]}
      else
        {lots, []}
      end

    {lots,
     %__MODULE__{
       port: port,
       good: good,
       merchant: merchant,
       seller: seller,
       buyer: buyer,
       stock: if(seller and not merchant, do: 500, else: 0),
       demand: if(buyer, do: 500, else: 0),
       budget: item["reference_cents"] * 1000,
       batches: batches,
       last_production: lots.clock_ms
     }}
  end

  def auction_supply(%Lots{} = lots, %__MODULE__{} = market, quantity, amount, item) do
    {lots, next, cargo} = supply(lots, market, quantity, 0, item)
    {lots, %{next | budget: next.budget + amount}, cargo}
  end

  def auction_consume(%__MODULE__{} = market, quantity, amount, cargo \\ nil) do
    true = market.buyer and market.demand >= quantity and market.budget >= amount
    next = receive_cargo(market, quantity, 0, cargo)
    %{next | budget: next.budget - amount}
  end

  def pay_storage(%__MODULE__{} = market, price) do
    true = market.merchant and is_integer(price) and price > 0 and market.budget >= price
    %{market | budget: market.budget - price}
  end

  def clear_merchant(%__MODULE__{merchant: true} = market), do: %{market | stock: 0, batches: []}

  @doc "Returns the market and the cycles charged against its credit, so callers never recompute them."
  def replenish(%Lots{} = lots, %__MODULE__{} = market, item, scale, quarters) do
    now = lots.clock_ms

    if item["id"] != market.good or now < market.last_production,
      do: raise(ArgumentError, "Market replenishment requires matching cargo and monotonic time")

    intervals = div(now - market.last_production, @market_replenishment_ms)

    {replenished, credit} =
      TijaraTides.Domain.Participation.cycles(intervals, scale, market.production_credit)

    batches = Enum.reject(market.batches, &(not is_nil(&1.expires_ms) and &1.expires_ms <= now))

    stock =
      if item["shelf_ms"] > 0,
        do: Enum.sum(Enum.map(batches, & &1.quantity)),
        else: market.stock

    market = %{market | batches: batches, stock: stock}

    if intervals > 0 do
      # Manufactured goods remain finite until recipes are implemented.
      produced =
        if market.good in raw_goods() and market.seller and not market.merchant,
          do: min(max(0, 500 - stock), replenished),
          else: 0

      {lots, batches} =
        if item["shelf_ms"] > 0 and produced > 0 do
          {next, lot} = Lots.create(lots, market.good, produced, now + item["shelf_ms"])
          {next, batches ++ [lot]}
        else
          {lots, batches}
        end

      {lots,
       %{
         market
         | stock: stock + produced,
           batches: batches,
           budget:
             min(
               div(
                 item["reference_cents"] * div(604_800_000 * quarters, @market_replenishment_ms) *
                   scale,
                 10_000
               ),
               market.budget +
                 if(market.buyer, do: replenished * item["reference_cents"], else: 0)
             ),
           demand:
             min(
               if(market.feedstock, do: max(0, 500 - stock - produced), else: 500),
               market.demand + if(market.buyer, do: replenished, else: 0)
             ),
           production_credit: credit,
           last_production: market.last_production + intervals * @market_replenishment_ms
       }, replenished}
    else
      {lots, market, 0}
    end
  end
end
