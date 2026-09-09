defmodule TijaraTides.Domain.Fleet do
  @moduledoc "Ship definitions, capacity, departure funding, voyages, and operating-cost settlement."
  import TijaraTides.Domain.State
  alias TijaraTides.Domain.Journal
  @asset_value 20_000_000
  @voyage_speedup 600
  @minimum_voyage_ms 6_000

  def classes do
    %{
      "freighter" => %{
        "name" => "Balanced freighter",
        "price" => 4_000_000,
        "weight" => 500_000,
        "volume" => 900_000,
        "hold" => "dry",
        "speed" => 22,
        "crew" => 30
      },
      "small_freighter" => %{
        "name" => "Small freighter",
        "price" => 3_000_000,
        "weight" => 200_000,
        "volume" => 400_000,
        "hold" => "dry",
        "speed" => 24,
        "crew" => 20
      },
      "bulk" => %{
        "name" => "Bulk carrier",
        "price" => 5_000_000,
        "weight" => 1_000_000,
        "volume" => 1_200_000,
        "hold" => "dry",
        "speed" => 18,
        "crew" => 40
      },
      "reefer" => %{
        "name" => "Small refrigerated ship",
        "price" => 5_000_000,
        "weight" => 200_000,
        "volume" => 400_000,
        "hold" => "reefer",
        "speed" => 24,
        "crew" => 35
      },
      "tanker" => %{
        "name" => "Small tanker",
        "price" => 5_000_000,
        "weight" => 500_000,
        "volume" => 650_000,
        "hold" => "liquid",
        "speed" => 20,
        "crew" => 35
      }
    }
  end

  def packages do
    %{
      "general" => ["freighter", "freighter", "freighter"],
      "bulk" => ["bulk", "bulk", "small_freighter"],
      "fresh" => ["reefer", "reefer", "freighter"],
      "oil" => ["tanker", "tanker", "freighter"]
    }
  end

  def package_cash(package),
    do: @asset_value - Enum.sum(Enum.map(packages()[package], &classes()[&1]["price"]))

  def capacity(ship, catalogue) do
    Enum.reduce(ship["cargo"], %TijaraTides.Domain.Capacity{}, fn batch, totals ->
      item = catalogue["goods"][batch["good"]]

      %TijaraTides.Domain.Capacity{
        weight: totals.weight + item["weight_kg"] * batch["quantity"],
        volume: totals.volume + item["volume_l"] * batch["quantity"]
      }
    end)
  end

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
    with {:ok, ship, company, estimate} <-
           departure_check(state, account, id, destination, limit, catalogue) do
      owner = company["id"]

      ship = %{
        ship
        | "status" => "sailing",
          "destination" => destination,
          "depart_ms" => state.clock_ms,
          "arrive_ms" => state.clock_ms + estimate["duration_ms"],
          "fuel_total" => estimate["fuel"],
          "fuel_burned" => 0
      }

      ship = Map.put(ship, "voyage_speedup", @voyage_speedup)

      state =
        state
        |> put("ships", id, ship)
        |> put("companies", owner, %{
          company
          | "reserved" => company["reserved"] + estimate["fuel"],
            "cash" => company["cash"] - estimate["canal_fees"],
            "profit" => company["profit"] - estimate["canal_fees"]
        })

      state =
        Journal.post(
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

      state = TijaraTides.Domain.ShipInstructions.depart(state, id, destination, catalogue)
      {:ok, state, %{"arrive_ms" => ship["arrive_ms"], "fuel" => estimate["fuel"]}}
    end
  end

  defp departure_check(state, account, id, destination, limit, catalogue) do
    ship = get(state, "ships", id)
    company = get(state, "companies", account["company_id"])

    cond do
      is_nil(ship) or is_nil(company) or ship["company_id"] != account["company_id"] ->
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

  # Older in-flight voyages used 60x. Preserve their progress when tuning changes;
  # the persisted multiplier prevents applying this adjustment on later ticks.
  defp retime_voyage(%{"status" => "sailing"} = ship, clock) do
    previous = Map.get(ship, "voyage_speedup", 60)

    if previous == @voyage_speedup do
      ship
    else
      ship
      |> Map.put(
        "depart_ms",
        clock - div((clock - ship["depart_ms"]) * previous, @voyage_speedup)
      )
      |> Map.put(
        "arrive_ms",
        clock + max(1, div((ship["arrive_ms"] - clock) * previous, @voyage_speedup))
      )
      |> Map.put("voyage_speedup", @voyage_speedup)
    end
  end

  defp retime_voyage(ship, _clock), do: ship

  def advance(state, elapsed) do
    now = state.clock_ms

    Enum.reduce(entities(state, "ships"), state, fn {id, ship}, state ->
      ship = retime_voyage(ship, now - elapsed)

      company =
        get(state, "companies", ship["company_id"]) ||
          raise(
            ArgumentError,
            "ship #{id} has no owning company; retire or transfer ships before removing a company"
          )

      class = classes()[ship["class"]]
      end_ms = ship["arrive_ms"] || now

      moving_ms =
        if ship["status"] == "sailing",
          do: max(0, min(now, end_ms) - ship["last_cost_ms"]),
          else: 0

      idle_ms = now - ship["last_cost_ms"] - moving_ms

      crew_numerator =
        ship["crew_remainder"] + moving_ms * class["crew"] * 2 + idle_ms * class["crew"]

      crew = div(crew_numerator, 120_000)

      fuel_burned =
        if ship["status"] == "sailing",
          do:
            max(
              ship["fuel_burned"],
              min(
                ship["fuel_total"],
                div(
                  ship["fuel_total"] * max(0, now - ship["depart_ms"]),
                  ship["arrive_ms"] - ship["depart_ms"]
                )
              )
            ),
          else: ship["fuel_burned"]

      fuel = fuel_burned - ship["fuel_burned"]
      cash = company["cash"] - fuel
      reserved = company["reserved"] - fuel
      paid = min(crew, max(0, cash - reserved))

      {expired, cargo} =
        Enum.split_with(ship["cargo"], &(&1["expires_ms"] != nil and &1["expires_ms"] <= now))

      spoilage = Enum.sum(Enum.map(expired, &(&1["unit_cost"] * &1["quantity"])))

      company = %{
        company
        | "cash" => cash - paid,
          "reserved" => reserved,
          "unpaid" => company["unpaid"] + crew - paid,
          "profit" => company["profit"] - crew - fuel - spoilage
      }

      ship = %{
        ship
        | "fuel_burned" => fuel_burned,
          "last_cost_ms" => now,
          "crew_remainder" => rem(crew_numerator, 120_000),
          "cargo" => cargo
      }

      ship =
        if ship["status"] != "docked" and end_ms <= now do
          %{
            ship
            | "port" => ship["destination"] || ship["port"],
              "destination" => nil,
              "status" => "docked",
              "arrive_ms" => nil,
              "depart_ms" => nil
          }
        else
          ship
        end

      state
      |> put("ships", id, ship)
      |> put("companies", company["id"], company)
      |> Journal.post(
        company["id"],
        "operations",
        [
          {"fuel_expense", fuel},
          {"cash_reserved", -fuel},
          {"crew_expense", crew},
          {"cash_available", -paid},
          {"payables", -(crew - paid)},
          {"spoilage_expense", spoilage},
          {"inventory", -spoilage}
        ],
        %{ship: id}
      )
    end)
  end
end
