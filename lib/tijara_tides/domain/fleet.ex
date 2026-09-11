defmodule TijaraTides.Domain.Fleet do
  @moduledoc "Ship definitions, capacity, departure funding, voyages, and operating-cost settlement."
  import TijaraTides.Domain.State
  alias TijaraTides.Domain.CompanyFinance
  @voyage_speedup 600
  @minimum_voyage_ms 6_000

  @useful_life_ms 28 * 86_400_000
  @residual_bps 2000
  @buyback_bps 9000

  def sale_value(ship, now) do
    basis = ship["build_value"] || ship["book_value"]
    age = max(0, now - (ship["built_ms"] || now))
    residual = div(basis * @residual_bps, 10_000)
    book = basis - div((basis - residual) * min(age, @useful_life_ms), @useful_life_ms)

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

      ship["status"] != "docked" or ship["cargo"] != [] or committed ->
        {:error, :ship_sale_unavailable}

      not is_integer(minimum) or minimum < 0 or
          sale_value(ship, state.clock_ms).proceeds < minimum ->
        {:error, :ship_sale_price_changed}

      true ->
        value = sale_value(ship, state.clock_ms)

        state =
          state
          |> TijaraTides.Domain.Ship.retire(id)
          |> CompanyFinance.post(
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

        {:ok, TijaraTides.Domain.CompanyFinance.settle(state),
         %{"sold" => id, "proceeds" => value.proceeds}}
    end
  end

  defdelegate classes(), to: TijaraTides.Domain.ShipClass, as: :all

  def purchase(state, account, class_id, port, price_limit, context) do
    state = TijaraTides.Domain.CompanyFinance.settle(state)
    company = get(state, "companies", account["company_id"])
    class = classes()[class_id]

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

      true ->
        count =
          Enum.count(entities(state, "ships"), fn {_, ship} ->
            ship["company_id"] == company["id"]
          end)

        ship = %{
          "id" => context.id,
          "company_id" => company["id"],
          "name" => "#{company["name"]} #{count + 1}",
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
          |> TijaraTides.Domain.Ship.store(TijaraTides.Domain.Ship.commission(ship))
          |> CompanyFinance.post(
            company["id"],
            "ship_purchase",
            [{"fleet", class["price"]}, {"cash_available", -class["price"]}],
            %{ship: ship["id"]}
          )

        {:ok, state, %{"ship_id" => ship["id"], "spent" => class["price"]}}
    end
  end

  def capacity(ship, catalogue),
    do: ship |> TijaraTides.Domain.Ship.from_row() |> TijaraTides.Domain.Ship.capacity(catalogue)

  def voyage_quote(ship, destination, catalogue) when is_binary(destination) do
    case catalogue["routes"][ship["port"] <> "|" <> destination] do
      nil ->
        nil

      route ->
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
          "route" => route
        }
    end
  end

  def voyage_quote(_ship, _destination, _catalogue), do: nil

  def sail(state, account, id, destination, limit, catalogue) do
    state = TijaraTides.Domain.CompanyFinance.settle(state)

    with {:ok, ship, company, estimate} <-
           departure_check(state, account, id, destination, limit, catalogue) do
      owner = company["id"]

      aggregate =
        ship
        |> TijaraTides.Domain.Ship.from_row()
        |> TijaraTides.Domain.Ship.begin_voyage(
          destination,
          estimate,
          state.clock_ms,
          @voyage_speedup
        )

      ship = TijaraTides.Domain.Ship.to_row(aggregate)

      state =
        state
        |> TijaraTides.Domain.Ship.store(aggregate)

      state =
        CompanyFinance.post(
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

      state = TijaraTides.Domain.Ship.consume_departure(state, id, destination, catalogue)
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

      {ship, effects} =
        TijaraTides.Domain.Ship.advance(
          TijaraTides.Domain.Ship.from_row(row),
          now,
          elapsed,
          company["bankruptcy_ms"] != nil,
          @voyage_speedup,
          value.book
        )

      state
      |> TijaraTides.Domain.Ship.store(ship)
      |> CompanyFinance.ship_operations(company["id"], id, effects)
    end)
  end
end
