defmodule TijaraTides.Domain.Fleet do
  alias TijaraTides.Domain.CompanyFinanceWorld
  alias TijaraTides.Domain.ShipMaintenance

  @moduledoc "Ship definitions, capacity, departure funding, voyages, and operating-cost settlement."
  import TijaraTides.Domain.State
  @voyage_speedup 600
  @minimum_voyage_ms 6_000

  @useful_life_ms ShipMaintenance.useful_life_ms()
  @residual_bps ShipMaintenance.residual_bps()
  @buyback_bps 9000

  # ShipMaintenance is internal to this boundary; Fleet is what Domain exports.
  defdelegate maintenance_estimate(ship, from_ms, to_ms), to: ShipMaintenance, as: :estimate
  defdelegate maintenance_forecast(ship, now), to: ShipMaintenance, as: :forecast
  defdelegate maintenance_curve(), to: ShipMaintenance, as: :curve

  def sale_value(ship, now) do
    basis = ship["acquisition_value"] || ship["build_value"] || ship["book_value"]
    age = max(0, now - (ship["acquired_ms"] || ship["built_ms"] || now))

    life =
      max(
        86_400_000,
        @useful_life_ms -
          max(0, (ship["acquired_ms"] || ship["built_ms"] || now) - (ship["built_ms"] || now))
      )

    residual = div(basis * @residual_bps, 10_000)
    book = basis - div((basis - residual) * min(age, life), life)

    %{
      book: min(ship["book_value"], book),
      proceeds: div(min(ship["book_value"], book) * @buyback_bps, 10_000)
    }
  end

  def sell(state, account, id, minimum) do
    ship = get(state, "ships", id)
    company = get(state, "companies", account["company_id"])

    committed =
      get(state, "ship_routes", id) != nil or
        Enum.any?(entities(state, "ship_instructions"), fn {_, order} ->
          order["ship_id"] == id and order["status"] in ["planned", "waiting"]
        end) or
        Enum.any?(entities(state, "visit_plans"), fn {_, plan} -> plan["ship_id"] == id end)

    cond do
      is_nil(ship) or is_nil(company) or ship["company_id"] != company["id"] or
        company["account_id"] != account["id"] or company["bankruptcy_ms"] != nil ->
        {:error, :ship_not_owned}

      ship["status"] != "docked" or ship["cargo"] != [] or not is_nil(ship["pending_side"]) or
          committed ->
        {:error, :ship_sale_unavailable}

      not is_integer(minimum) or minimum < 0 or
          sale_value(ship, state.clock_ms).proceeds < minimum ->
        {:error, :ship_sale_price_changed}

      true ->
        value = sale_value(ship, state.clock_ms)

        state =
          state
          |> TijaraTides.Domain.ShipWorld.retire(id)
          |> CompanyFinanceWorld.post(
            company["id"],
            "ship_sale",
            [
              {"cash_available", value.proceeds},
              {"fleet", -ship["book_value"]},
              {"depreciation_expense", ship["book_value"] - value.book},
              {"ship_disposal_expense", value.book - value.proceeds}
            ],
            %{ship: id}
          )

        {:ok,
         TijaraTides.Domain.Services.FinancialSettlement.settle(state, [account["company_id"]]),
         %{"sold" => id, "proceeds" => value.proceeds}}
    end
  end

  defdelegate classes(), to: TijaraTides.Domain.ShipClass, as: :all

  def purchase(state, account, class_id, port, price_limit, context, name \\ nil) do
    state = TijaraTides.Domain.Services.FinancialSettlement.settle(state, [account["company_id"]])
    company = get(state, "companies", account["company_id"])
    class = classes()[class_id]
    name = if is_binary(name), do: String.trim(name), else: name
    name = if name in [nil, ""], do: next_ship_name(state, (company || %{})["name"]), else: name
    checked_name = validate_ship_name(state, name)

    cond do
      is_nil(company) or company["account_id"] != account["id"] or company["bankruptcy_ms"] != nil ->
        {:error, :ship_company_unavailable}

      is_nil(class) ->
        {:error, :ship_class_invalid}

      not Map.has_key?(context.catalogue["ports"], port) ->
        {:error, :invalid_port}

      not is_integer(price_limit) or price_limit < class["price"] ->
        {:error, :ship_price_changed}

      company["cash"] - company["reserved"] < class["price"] ->
        {:error, :ship_purchase_funds}

      get(state, "ships", context.id) != nil ->
        {:error, :ship_id_conflict}

      match?({:error, _}, checked_name) ->
        checked_name

      true ->
        {:ok, name} = checked_name

        ship = %{
          "id" => context.id,
          "company_id" => company["id"],
          "name" => name,
          "class" => class_id,
          "book_value" => class["price"],
          "build_value" => class["price"],
          "built_ms" => state.clock_ms,
          "port" => port,
          "cargo" => [],
          "status" => "docked",
          "arrive_ms" => nil,
          "destination" => nil,
          "depart_ms" => nil,
          "fuel_total" => 0,
          "fuel_burned" => 0,
          "crew_remainder" => 0,
          "last_cost_ms" => state.clock_ms,
          "last_liquid" => nil
        }

        state =
          state
          |> TijaraTides.Domain.ShipWorld.commission(ship)
          |> CompanyFinanceWorld.post(
            company["id"],
            "ship_purchase",
            [{"fleet", class["price"]}, {"cash_available", -class["price"]}],
            %{ship: ship["id"]}
          )

        {:ok, state, %{"ship_id" => ship["id"], "spent" => class["price"]}}
    end
  end

  def validate_ship_name(state, name, except_id \\ nil) do
    name = if is_binary(name), do: String.trim(name), else: ""

    cond do
      name == "" or String.length(name) > 80 or String.match?(name, ~r/[\p{Cc}\p{Cf}]/u) ->
        {:error, :ship_name_invalid}

      Enum.any?(entities(state, "ships"), fn {id, ship} ->
        id != except_id and ship["name"] == name
      end) ->
        {:error, :ship_name_taken}

      true ->
        {:ok, name}
    end
  end

  defp next_ship_name(state, company_name) do
    names = MapSet.new(entities(state, "ships"), fn {_, ship} -> ship["name"] end)

    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(&"#{company_name} #{&1}")
    |> Enum.find(&(not MapSet.member?(names, &1)))
  end

  def capacity(ship, catalogue) do
    cargo = Enum.map(ship["cargo"] || [], &TijaraTides.Domain.Ship.CargoRows.coerce/1)
    TijaraTides.Domain.Ship.capacity(%TijaraTides.Domain.Ship{cargo: cargo}, catalogue)
  end

  def voyage_quote(ship, destination, catalogue, clock \\ nil)

  def voyage_quote(ship, destination, catalogue, clock) when is_binary(destination) do
    case catalogue["routes"][ship["port"] <> "|" <> destination] do
      nil ->
        nil

      route ->
        route_quote(ship, route, catalogue, clock)
    end
  end

  def voyage_quote(_ship, _destination, _catalogue, _clock), do: nil

  defp route_quote(ship, route, catalogue, clock) do
    aged = clock || ship["last_cost_ms"] || 0

    class = classes()[ship["class"]]
    space = capacity(ship, catalogue)
    fuel = route["nautical_miles"] * (8 + div(space.weight * 8, class["weight"]))

    duration =
      max(
        @minimum_voyage_ms,
        div(route["nautical_miles"] * 3_600_000, class["speed"] * @voyage_speedup)
      )

    %{
      "fuel" => fuel,
      "canal_fees" => Enum.count(route["passages"], &(&1 in ["panama", "suez"])) * 25_000,
      "duration_ms" => duration,
      "crew_estimate" => div(duration * class["crew"], 60_000),
      # Age the estimate from the caller's clock. The settlement cursor stands in only
      # for funding and automation checks, which build synthetic ships and never read it.
      "maintenance_estimate" => ShipMaintenance.estimate(ship, aged, aged + duration),
      "route" => route
    }
  end

  def reroute_quote(ship, destination, clock, catalogue) do
    case TijaraTides.Domain.VoyageNavigation.reroute(ship, clock, destination, catalogue) do
      nil ->
        nil

      route ->
        quote = route_quote(ship, route, catalogue, clock)
        paid = paid_canals(ship, catalogue)

        fees =
          Enum.count(route["passages"], fn p -> Bitwise.band(paid, canal_bit(p)) == 0 end) *
            25_000

        delta = quote["fuel"] - (ship["fuel_total"] - ship["fuel_burned"])

        quote
        |> Map.put("canal_fees", fees)
        |> Map.put("additional_fuel", max(0, delta))
        |> Map.put("released_fuel", max(0, -delta))
    end
  end

  defdelegate canal_bit(passage), to: TijaraTides.Domain.Ship

  def paid_canals(ship, catalogue) do
    ship["paid_canals"] ||
      Enum.reduce(
        get_in(catalogue, ["routes", ship["port"] <> "|" <> ship["destination"], "passages"]) ||
          [],
        0,
        fn p, n -> Bitwise.bor(n, canal_bit(p)) end
      )
  end

  def reroute(state, account, id, destination, limit, catalogue) do
    ship = get(state, "ships", id)
    company = get(state, "companies", account["company_id"])

    with true <-
           ship != nil and company != nil and ship["company_id"] == company["id"] and
             is_nil(company["bankruptcy_ms"]),
         true <- ship["status"] == "sailing",
         %{} = quote <- reroute_quote(ship, destination, state.clock_ms, catalogue),
         true <- is_integer(limit) and limit >= quote["fuel"],
         true <- quote["duration_ms"] <= 86_400_000 do
      delta = quote["fuel"] - (ship["fuel_total"] - ship["fuel_burned"])

      if company["cash"] - company["reserved"] < delta + quote["canal_fees"] or
           (company["unpaid"] > 0 and delta + quote["canal_fees"] > 0) do
        {:error, :reroute_funds}
      else
        paid =
          Enum.reduce(quote["route"]["passages"], paid_canals(ship, catalogue), fn p, n ->
            Bitwise.bor(n, canal_bit(p))
          end)

        state = TijaraTides.Domain.ShipWorld.reroute(state, id, destination, quote, paid)

        state =
          CompanyFinanceWorld.post(
            state,
            company["id"],
            "reroute",
            [
              {"cash_reserved", delta},
              {"cash_available", -delta - quote["canal_fees"]},
              {"canal_expense", quote["canal_fees"]}
            ],
            %{ship: id}
          )

        state = TijaraTides.Domain.ShipWorld.pause_diverted_route(state, id)

        {:ok, state, %{"arrive_ms" => state.clock_ms + quote["duration_ms"]}}
      end
    else
      _ -> {:error, :reroute_invalid}
    end
  end

  def sail(state, account, id, destination, limit, catalogue) do
    state = TijaraTides.Domain.Services.FinancialSettlement.settle(state, [account["company_id"]])

    with {:ok, _ship, company, estimate} <-
           departure_check(state, account, id, destination, limit, catalogue) do
      owner = company["id"]

      state =
        TijaraTides.Domain.ShipWorld.depart(state, id, destination, estimate, @voyage_speedup)

      ship = get(state, "ships", id)

      state =
        CompanyFinanceWorld.post(
          state,
          owner,
          "departure",
          [
            {"cash_reserved", estimate["fuel"]},
            {"cash_available", -estimate["fuel"] - estimate["canal_fees"]},
            {"canal_expense", estimate["canal_fees"]}
          ],
          %{ship: id}
        )

      state = TijaraTides.Domain.ShipWorld.consume_departure(state, id, destination, catalogue)
      {:ok, state, %{"arrive_ms" => ship["arrive_ms"], "fuel" => estimate["fuel"]}}
    end
  end

  defp departure_check(state, account, id, destination, limit, catalogue) do
    ship = get(state, "ships", id)
    company = get(state, "companies", account["company_id"])

    cond do
      is_nil(ship) or is_nil(company) or company["bankruptcy_ms"] != nil or
          ship["company_id"] != account["company_id"] ->
        {:error, :departure_ship_unavailable}

      not is_nil(ship["pending_side"]) ->
        {:error, :berth_order_pending}

      ship["status"] != "docked" ->
        {:error,
         {:departure_busy, ship["status"],
          max(0, (ship["arrive_ms"] || state.clock_ms) - state.clock_ms)}}

      not is_binary(destination) or not Map.has_key?(catalogue["ports"], destination) ->
        {:error, :departure_destination_invalid}

      destination == ship["port"] ->
        {:error, {:departure_already_here, destination}}

      true ->
        case voyage_quote(ship, destination, catalogue) do
          nil -> {:error, {:departure_no_route, ship["port"], destination}}
          estimate -> departure_funding(ship, company, estimate, limit)
        end
    end
  end

  defp departure_funding(ship, company, estimate, limit) do
    available = company["cash"] - company["reserved"]
    required = estimate["fuel"] + estimate["canal_fees"]

    cond do
      not is_integer(limit) or limit < 0 ->
        {:error, :departure_fuel_limit_invalid}

      limit < estimate["fuel"] ->
        {:error, {:departure_fuel_limit, estimate["fuel"], limit}}

      estimate["duration_ms"] > 86_400_000 ->
        {:error, {:departure_too_long, estimate["duration_ms"]}}

      company["unpaid"] > 0 ->
        {:error, {:departure_unpaid, company["unpaid"]}}

      available < required ->
        {:error, {:departure_funds, estimate["fuel"], estimate["canal_fees"], available}}

      true ->
        {:ok, ship, company, estimate}
    end
  end

  def advance(state, elapsed) do
    now = state.clock_ms

    Enum.reduce(entities(state, "ships"), state, fn {id, row}, state ->
      company =
        get(state, "companies", row["company_id"]) ||
          raise(
            ArgumentError,
            "ship #{id} has no owning company; retire or transfer ships before removing a company"
          )

      value = sale_value(row, now)

      {state, effects} =
        TijaraTides.Domain.ShipWorld.advance_hull(
          state,
          id,
          elapsed,
          company["bankruptcy_ms"] != nil,
          @voyage_speedup,
          value.book
        )

      state =
        if row["status"] in ["loading", "unloading"] and row["arrive_ms"] <= now and
             get_in(get(state, "ship_routes", id) || %{}, ["status"]) != "running" do
          code = if row["status"] == "loading", do: "ship.loaded", else: "ship.unloaded"

          TijaraTides.Domain.Notices.notice(
            state,
            company["account_id"],
            "handling:" <> id <> ":" <> to_string(row["arrive_ms"]),
            {code, %{"ship" => row["name"], "port" => row["port"]}}
          )
        else
          state
        end

      state
      |> CompanyFinanceWorld.ship_operations(company["id"], id, effects)
    end)
  end
end
