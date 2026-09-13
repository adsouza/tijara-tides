defmodule TijaraTides.Domain.Warehouse do
  @moduledoc "Finite port storage leases with typed cargo, prepaid rent and preserved lot identity."
  import TijaraTides.Domain.State
  alias TijaraTides.Domain.{CompanyFinance, Ship, CargoRules, PortBerths}
  alias TijaraTides.Domain.Ship.CargoBatch
  @day 86_400_000
  @terms [1, 3, 7]
  @storage_classes ["dry", "reefer", "liquid"]
  @max_lots CargoRules.max_lots()
  @fields ~w(id company_id port storage good blocks started_ms expires_ms rent prepaid protected_ms)a
  @enforce_keys @fields
  defstruct @fields ++ [cargo: []]

  def from_row(row) do
    unknown = Map.keys(row) -- ["cargo" | Enum.map(@fields, &Atom.to_string/1)]
    if unknown != [], do: raise(ArgumentError, "Unknown warehouse fields")

    struct!(
      __MODULE__,
      Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))})
      |> Map.put(:cargo, Enum.map(row["cargo"], &CargoBatch.from_row/1))
    )
  end

  def to_row(w),
    do:
      Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(w, &1)})
      |> Map.put("cargo", Enum.map(w.cargo, &CargoBatch.to_row/1))

  defp save(state, w), do: put(state, "warehouses", w.id, to_row(w))
  def block_litres, do: 100_000
  def terms, do: @terms
  def pool("dry"), do: %{blocks: 1000, rate: 100}
  def pool("reefer"), do: %{blocks: 250, rate: 300}
  def pool("liquid"), do: %{blocks: 500, rate: 200}
  def pool(_), do: nil

  def pools(state) do
    entities(state, "warehouses")
    |> Map.values()
    |> Enum.group_by(&{&1["port"], &1["storage"]})
    |> Map.new(fn {{port, storage}, rows} ->
      {port <> "|" <> storage, Enum.sum(Enum.map(rows, & &1["blocks"]))}
    end)
  end

  @doc "Blocks leased in one pool, without building the world-wide utilization map."
  def used(state, port, storage) do
    Enum.sum(
      for {_, row} <- entities(state, "warehouses"),
          row["port"] == port and row["storage"] == storage,
          do: row["blocks"]
    )
  end

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

  def lease(state, account, cmd, id, catalogue) do
    company = get(state, "companies", account["company_id"])
    storage = cmd["storage"]

    well_formed =
      storage in @storage_classes and is_integer(cmd["blocks"]) and cmd["blocks"] > 0 and
        cmd["days"] in @terms

    price =
      if well_formed,
        do: quote(used(state, cmd["port"], storage), storage, cmd["blocks"], cmd["days"])

    cond do
      is_nil(company) or company["bankruptcy_ms"] != nil ->
        {:error, :finance_no_company}

      not well_formed or is_nil(catalogue["ports"][cmd["port"]]) ->
        {:error, :warehouse_invalid}

      storage == "liquid" and get_in(catalogue, ["goods", cmd["good"], "hold"]) != "liquid" ->
        {:error, :incompatible_cargo}

      is_nil(price) ->
        {:error, :warehouse_capacity}

      price != cmd["price"] ->
        {:error, :price_changed}

      company["cash"] - company["reserved"] < price or company["unpaid"] > 0 ->
        {:error, :insufficient_cash}

      get(state, "warehouses", id) != nil ->
        {:error, :warehouse_invalid}

      true ->
        w = %__MODULE__{
          id: id,
          company_id: company["id"],
          port: cmd["port"],
          storage: storage,
          good: if(storage == "liquid", do: cmd["good"]),
          blocks: cmd["blocks"],
          started_ms: state.clock_ms,
          expires_ms: state.clock_ms + cmd["days"] * @day,
          rent: price,
          prepaid: price,
          protected_ms: state.clock_ms
        }

        state =
          save(state, w)
          |> CompanyFinance.post(company["id"], "warehouse_lease", [
            {"prepaid_rent", price},
            {"cash_available", -price}
          ])

        {:ok, state, %{}}
    end
  end

  def volume(w, catalogue),
    do: Enum.sum(for b <- w.cargo, do: b.quantity * catalogue["goods"][b.good]["volume_l"])

  def compatible?(w, item),
    do: item["hold"] == w.storage and (w.storage != "liquid" or item["id"] == w.good)

  def release(state, account, id, blocks, catalogue) do
    with %{"company_id" => owner} = row <- get(state, "warehouses", id),
         true <- owner == account["company_id"],
         true <- is_integer(blocks) and blocks > 0 and blocks <= row["blocks"] do
      company = get(state, "companies", owner)
      w = from_row(row)

      cond do
        is_nil(company) or company["bankruptcy_ms"] != nil ->
          {:error, :finance_no_company}

        company["unpaid"] > 0 ->
          {:error, :insufficient_cash}

        state.clock_ms < w.protected_ms or
            volume(w, catalogue) > (w.blocks - blocks) * block_litres() ->
          {:error, :warehouse_occupied}

        true ->
          {state, w} = accrue(state, w)
          remaining_rent = div(w.rent * (w.blocks - blocks), w.blocks)

          remaining_prepaid =
            div(
              remaining_rent * max(0, w.expires_ms - state.clock_ms),
              max(1, w.expires_ms - w.started_ms)
            )

          forfeited = w.prepaid - remaining_prepaid
          refund = div(forfeited, 2)

          state =
            CompanyFinance.post(state, owner, "warehouse_release", [
              {"prepaid_rent", -forfeited},
              {"cash_available", refund},
              {"rent_expense", forfeited - refund}
            ])

          state =
            if blocks == w.blocks,
              do: delete(state, "warehouses", id),
              else:
                save(state, %{
                  w
                  | blocks: w.blocks - blocks,
                    rent: remaining_rent,
                    prepaid: remaining_prepaid
                })

          {:ok, state, %{"refund" => refund}}
      end
    else
      _ -> {:error, :warehouse_invalid}
    end
  end

  def transfer(state, account, cmd, catalogue) do
    with %{"company_id" => owner} = row <- get(state, "warehouses", cmd["warehouse"]),
         true <- owner == account["company_id"],
         %{"company_id" => ^owner, "status" => "docked"} = ship <-
           get(state, "ships", cmd["ship"]),
         true <- ship["port"] == row["port"],
         %{} = item <- catalogue["goods"][cmd["good"]],
         n when is_integer(n) and n > 0 and n <= @max_lots <- cmd["quantity"],
         side when side in ["store", "collect"] <- cmd["side"] do
      w = from_row(row)
      company = get(state, "companies", owner)

      cleaning = if side == "collect", do: cleaning_cost(ship, item), else: 0

      fee =
        cleaning +
          n * TijaraTides.Domain.PortCargoMarket.handling_rate(catalogue["ports"][w.port])

      # Collection offers only unspoiled lots, so take/4 must walk that same list: given the
      # whole manifest it matches on good alone and drains expired batches the count excluded.
      {fresh, stale} =
        Enum.split_with(w.cargo, &(is_nil(&1.expires_ms) or &1.expires_ms > state.clock_ms))

      available =
        if side == "store",
          do: Ship.cargo_available(state, ship["id"], item["id"]),
          else: Enum.sum(for b <- fresh, b.good == item["id"], do: b.quantity)

      cond do
        company["bankruptcy_ms"] != nil ->
          {:error, :finance_no_company}

        state.clock_ms < w.protected_ms ->
          {:error, :warehouse_handling}

        state.clock_ms >= max(w.expires_ms, w.protected_ms) + div(@day, 2) ->
          {:error, :warehouse_expired}

        side == "store" and state.clock_ms >= w.expires_ms ->
          {:error, :warehouse_expired}

        not compatible?(w, item) or not CargoRules.compatible_cargo?(ship, item) ->
          {:error, :incompatible_cargo}

        available < n ->
          {:error, :insufficient_cargo}

        side == "store" and
            volume(w, catalogue) + n * item["volume_l"] > w.blocks * block_litres() ->
          {:error, :warehouse_capacity}

        side == "collect" and not fits?(ship, item, n, catalogue) ->
          {:error, :capacity_exceeded}

        company["cash"] - company["reserved"] < fee or company["unpaid"] > 0 ->
          {:error, :insufficient_cash}

        not PortBerths.available?(state, ship, catalogue) ->
          {:error, :warehouse_berth_busy}

        true ->
          {state, w} =
            if side == "store" do
              {s, cargo} = Ship.unload_cargo(state, ship["id"], item["id"], n)
              {s, %{w | cargo: w.cargo ++ Enum.map(cargo, &CargoBatch.from_row/1)}}
            else
              {s, cargo, left} = CargoBatch.take(state, fresh, n, item["id"])

              {Ship.load_cargo(
                 s,
                 ship["id"],
                 Enum.map(cargo, &CargoBatch.to_row/1),
                 cleaning,
                 catalogue
               ), %{w | cargo: left ++ stale}}
            end

          w = %{w | protected_ms: get(state, "ships", ship["id"])["arrive_ms"]}

          state =
            save(state, w)
            |> Ship.admit_handling(ship["id"])
            |> CompanyFinance.post(
              owner,
              "warehouse_transfer",
              [{"handling_expense", fee}, {"cash_available", -fee}],
              %{ship: ship["id"], good: item["id"]}
            )

          {:ok, state, %{}}
      end
    else
      _ -> {:error, :warehouse_invalid}
    end
  end

  def cleaning_cost(ship, item) do
    if item["hold"] == "liquid" and ship["last_liquid"] not in [nil, item["id"]],
      do: if("vegetable_oil" in [ship["last_liquid"], item["id"]], do: 25_000, else: 5000),
      else: 0
  end

  defp fits?(ship, item, n, catalogue) do
    used = TijaraTides.Domain.Fleet.capacity(ship, catalogue)
    class = TijaraTides.Domain.Fleet.classes()[ship["class"]]

    used.weight + n * item["weight_kg"] <= class["weight"] and
      used.volume + n * item["volume_l"] <= class["volume"]
  end

  defp accrue(state, w) do
    remaining =
      if w.expires_ms <= w.started_ms,
        do: 0,
        else: div(w.rent * max(0, w.expires_ms - state.clock_ms), w.expires_ms - w.started_ms)

    amount = w.prepaid - remaining

    {CompanyFinance.post(state, w.company_id, "warehouse_rent", [
       {"prepaid_rent", -amount},
       {"rent_expense", amount}
     ]), %{w | prepaid: remaining}}
  end

  def advance(state, catalogue) do
    Enum.reduce(entities(state, "warehouses"), state, fn {_, row}, state ->
      {state, w} = accrue(state, from_row(row))

      state =
        if row["prepaid"] > 0 and w.prepaid == 0 do
          TijaraTides.Domain.Notices.notice(
            state,
            get(state, "companies", w.company_id)["account_id"],
            "warehouse:" <> w.id,
            {"warehouse.expired", %{"port" => w.port}}
          )
        else
          state
        end

      {expired, cargo} =
        Enum.split_with(w.cargo, &(&1.expires_ms != nil and &1.expires_ms <= state.clock_ms))

      lost = Enum.sum(for b <- expired, do: b.quantity * b.unit_cost)

      state =
        if lost > 0,
          do:
            CompanyFinance.post(state, w.company_id, "warehouse_spoilage", [
              {"inventory", -lost},
              {"spoilage_expense", lost}
            ]),
          else: state

      w = %{w | cargo: cargo}
      bankrupt = get(state, "companies", w.company_id)["bankruptcy_ms"] != nil

      if state.clock_ms >= w.protected_ms and
           (state.clock_ms >= w.expires_ms + div(@day, 2) or bankrupt) do
        # System clearance is the initial liquidation adapter; auctions come later. It faces
        # no buyer, so it has neither depth nor slippage and would otherwise be a fixed price
        # floor: cap proceeds at cost so abandoning stock can never mint cash when a port's
        # ask has drifted below half reference.
        cost = Enum.sum(for b <- cargo, do: b.quantity * b.unit_cost)

        value =
          Enum.sum(
            for b <- cargo,
                do:
                  b.quantity *
                    min(b.unit_cost, div(catalogue["goods"][b.good]["reference_cents"], 2))
          )

        grace =
          div(w.rent * max(0, state.clock_ms - w.expires_ms), max(1, w.expires_ms - w.started_ms))

        charges = min(value, grace)

        state
        |> TijaraTides.Domain.Notices.notice(
          get(state, "companies", w.company_id)["account_id"],
          "warehouse:" <> w.id,
          {"warehouse.cleared", %{"port" => w.port, "refund" => value - charges}}
        )
        |> delete("warehouses", w.id)
        |> CompanyFinance.post(w.company_id, "warehouse_clearance", [
          {"inventory", -cost},
          {"cost_of_goods", cost},
          {"sales_revenue", -value},
          {"cash_available", value - charges},
          {"rent_expense", charges + w.prepaid},
          {"prepaid_rent", -w.prepaid}
        ])
      else
        save(state, w)
      end
    end)
  end
end
