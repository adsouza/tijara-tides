defmodule TijaraTidesWeb.GameUI.Presentation do
  @moduledoc "Shared formatting and display calculations for the game panels."
  use TijaraTidesWeb, :html
  alias TijaraTides.UseCases.{Game, GameQueries}

  def bounded_quantity(_quantity, maximum) when maximum < 1, do: 0
  def bounded_quantity(quantity, maximum), do: max(1, min(quantity, maximum))

  def owns_ship_at_port?(nil, _port), do: false

  def owns_ship_at_port?(private, port) do
    Enum.any?(private["ships"], fn {_, ship} ->
      ship["port"] == port and ship["status"] != "sailing"
    end)
  end

  # Keep persisted good IDs stable when their player-facing names change.
  def cargo_name(good), do: Game.cargo_name(good)

  def route_distance(definitions, ship, destination),
    do: GameQueries.route_distance(definitions, ship, destination)

  def cargo_markets(definitions, view, good, side, sort, ship),
    do: GameQueries.cargo_markets(definitions, view, good, side, sort, ship)

  def cargo_roi(nil), do: "—"
  def cargo_roi(roi), do: :erlang.float_to_binary(roi * 100, decimals: 2) <> "%"

  def visible_market_rows(definitions, view, ship, port),
    do: GameQueries.visible_market_rows(definitions, view, ship, port)

  def cargo_aboard(ship, good), do: GameQueries.cargo_aboard(ship, good)
  def sorted_manifest(cargo, goods, sort), do: GameQueries.sorted_manifest(cargo, goods, sort)

  def manifest(cargo), do: GameQueries.manifest(cargo, Game.definitions().catalogue)

  def instruction_port(nil, _destination, _definitions), do: nil

  def instruction_port(ship, destination, definitions) do
    port = ship["destination"] || destination

    if is_binary(port) and port != ship["port"] and
         Map.has_key?(definitions.catalogue["ports"], port),
       do: port
  end

  def instruction_cents(value) do
    case Decimal.parse(to_string(value)) do
      {amount, ""} -> amount |> Decimal.mult(100) |> Decimal.round(0) |> Decimal.to_integer()
      _ -> 0
    end
  end

  def instruction_value(drafts, ship, key, default),
    do: Map.get(Map.get(drafts, ship["id"], %{}), key, default)

  def ship_instructions(private, ship_id) do
    private["ship_instructions"]
    |> Map.values()
    |> Enum.filter(&(&1["ship_id"] == ship_id))
    |> Enum.sort_by(
      &{if(&1["status"] in ["planned", "waiting"], do: 0, else: 1), -&1["created_ms"], &1["id"]}
    )
    |> Enum.take(40)
  end

  def cubic_meters(litres) do
    whole = Integer.to_string(div(litres, 1000))

    fraction =
      rem(litres, 1000)
      |> Integer.to_string()
      |> String.pad_leading(3, "0")
      |> String.trim_trailing("0")

    whole <> if(fraction == "", do: "", else: "." <> fraction) <> " m³"
  end

  def cargo_volume(item, quantity) do
    litres = item["volume_l"] * quantity
    if item["hold"] == "liquid", do: "#{litres} L", else: cubic_meters(litres)
  end

  attr :estimates, :list, required: true
  attr :id, :string, required: true

  def voyage_freshness(assigns) do
    ~H"""
    <details
      :if={@estimates != []}
      id={@id}
      phx-mounted={JS.ignore_attributes("open")}
      class="voyage-freshness mt-3 w-full text-sm text-amber-200"
    >
      <summary class="cursor-pointer">Cargo freshness</summary>
      <p :for={estimate <- @estimates}>
        {cargo_name(estimate["good"])}: estimated time to first expiry — {minutes(
          estimate["arrival_ms"]
        )} min at arrival; {minutes(estimate["unloaded_ms"])} min after unloading.
        <strong :if={estimate["unloaded_ms"] == 0}>Spoilage expected before unloading finishes.</strong>
      </p>
      <p class="text-xs">
        Assumes unloading all current cargo. Estimates update with the voyage and may change with delays.
      </p>
    </details>
    """
  end

  def integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> -1
    end
  end

  def integer(_), do: -1
  def dollars(whole), do: "$" <> Integer.to_string(whole)
  def money(cents), do: dollars(round(cents / 100))

  def finance_money(cents),
    do:
      dollars(div(cents, 100)) <>
        "." <> String.pad_leading(Integer.to_string(rem(cents, 100)), 2, "0")

  def minutes(ms), do: Float.round(ms / 60000, 1)

  def invitation_time_remaining(ms) do
    seconds = div(max(0, ms), 1000)

    cond do
      seconds >= 86_400 ->
        days = div(seconds, 86_400)
        "~#{days} #{if days == 1, do: "day", else: "days"}"

      seconds >= 3600 ->
        hours = div(seconds, 3600)
        "~#{hours} #{if hours == 1, do: "hour", else: "hours"}"

      seconds >= 60 ->
        minutes = div(seconds, 60)
        "#{minutes} #{if minutes == 1, do: "min", else: "mins"}"

      true ->
        "#{seconds} #{if seconds == 1, do: "sec", else: "secs"}"
    end
  end

  def active_countdown(ms) do
    seconds = div(max(0, ms) + 999, 1000)

    [div(seconds, 3600), div(rem(seconds, 3600), 60), rem(seconds, 60)]
    |> Enum.map_join(":", &(Integer.to_string(&1) |> String.pad_leading(2, "0")))
  end

  @doc false
  def error_message({:departure_busy, status, remaining}) do
    action =
      case status do
        "sailing" -> "already sailing"
        "loading" -> "still loading cargo"
        "unloading" -> "still unloading cargo"
        _ -> "not docked (#{status})"
      end

    "This ship is #{action}. " <>
      if(remaining > 0,
        do: "It will be ready in about #{ceil(remaining / 1000)} seconds.",
        else: "Wait for its status to update before departing."
      )
  end

  def error_message({:departure_already_here, port}),
    do: "This ship is already at #{port}. Choose a different destination."

  def error_message({:purchase_voyage_funds, destination, required, remaining}),
    do:
      "This purchase would leave #{money(remaining)}, but the voyage to #{destination} needs #{money(required)} for fuel, canal fees, and estimated fleet upkeep. Buy fewer lots."

  def error_message({:departure_no_route, from, destination}),
    do:
      "There is no available sea route from #{from} to #{destination}. Choose another destination."

  def error_message({:departure_fuel_limit, fuel, limit}),
    do:
      "Fuel now requires #{money(fuel)}, above the confirmed limit of #{money(limit)}. Review the voyage estimate and confirm again."

  def error_message({:departure_too_long, duration}),
    do:
      "This route would take #{minutes(duration)} minutes, exceeding the 24-hour voyage limit. Choose a closer destination."

  def error_message({:departure_unpaid, unpaid}),
    do:
      "Your company owes #{money(unpaid)} in unpaid operating costs. Sell cargo to settle those costs before departing."

  def error_message({:departure_funds, fuel, canal, available}) do
    # Whole dollars must not flatter the player: round each cost up and the cash
    # they hold down, so a stated shortfall is always enough to cover departure.
    # Every figure here is derived from the two costs, which keeps the message's
    # own arithmetic true — a breakdown that did not sum to its total, or a
    # one-cent gap reported as $0, would each read as a contradiction.
    fuel_dollars = ceil(fuel / 100)
    canal_dollars = ceil(canal / 100)
    needed = fuel_dollars + canal_dollars
    held = floor(available / 100)

    "Departure requires #{dollars(needed)}: #{dollars(fuel_dollars)} for fuel and " <>
      "#{dollars(canal_dollars)} in canal fees. You have #{dollars(held)} available " <>
      "after reservations, leaving a shortfall of #{dollars(needed - held)}."
  end

  def error_message(reason) do
    %{
      loan_recast_unavailable:
        "Clear overdue bills before recasting. The loan must still have scheduled payments remaining.",
      loan_recast_amount:
        "Pay accrued interest plus at least $1 of principal, up to the outstanding balance. Review the current amounts and try again.",
      account_suspended:
        "Account suspended. Your original sponsor must fund a cash guarantee to reinstate you.",
      guarantee_not_sponsor: "Only the player's original inviter can provide this guarantee.",
      guarantee_sponsor_unavailable:
        "Your company must be active with no overdue bills, and unreserved cash must cover your own outstanding loan principal and interest.",
      guarantee_not_required: "This player does not currently need a guarantee.",
      guarantee_exists: "This player already has an active guarantee.",
      guarantee_amount: "Pledge at least $50,000, up to the player's normal credit limit.",
      guarantee_funds: "Not enough unreserved cash to fund this guarantee.",
      ship_sale_unavailable:
        "Dock and empty the ship, then clear pending cargo instructions, onward plans and repeating routes before selling.",
      ship_sale_price_changed:
        "The shipyard offer has changed. Review the current value and try again.",
      ship_company_unavailable: "Create an active company before buying a ship.",
      ship_class_invalid: "Choose an available ship class.",
      ship_price_changed: "The ship price has changed. Review it before buying.",
      ship_purchase_funds:
        "Not enough unreserved cash to buy this ship. Borrow first and retain funds for cargo and voyages.",
      ship_id_conflict: "This ship purchase has already been processed.",
      bankruptcy_cash_covers_debts:
        "Available cash covers all loan principal, accrued interest and unpaid operating bills. Bankruptcy is unavailable.",
      instruction_ship_not_owned: "Select a ship owned by your company.",
      instruction_destination_invalid:
        "Choose the ship's next destination; a sailing ship can only use its current destination.",
      email_invalid: "Enter a valid email address.",
      email_unavailable:
        "That email cannot be linked or invited. Its owner can use email sign-in instead.",
      email_rate_limited: "Too many email requests. Please try again later.",
      route_ship_not_owned: "Choose a ship owned by your active company.",
      route_stop_committed:
        "This stop belongs to the current visit or next leg. Edit it after the ship advances.",
      route_edit_draft:
        "Route stops can be edited before starting. Remove the route to replace its plan; committed handling continues.",
      route_existing_instructions:
        "Finish or cancel next-port instructions and clear their onward plan before creating a repeating route.",
      route_owns_instructions:
        "This ship uses a repeating route. Use its route controls instead.",
      route_stop_limit: "A repeating route can have up to eight stops.",
      route_port_invalid:
        "Choose a valid port with a sea route; consecutive stops must be different.",
      route_duplicate_rule:
        "Use one target per cargo and action at each stop, with at most twenty targets per stop.",
      route_needs_stops:
        "Add at least two stops. The last stop returns to the first, so they must differ.",
      route_start_port:
        "The ship must be at, or sailing toward, the route's selected stop to start or resume.",
      route_missing: "This ship has no saved repeating route.",
      instruction_duplicate_sell:
        "An active sell instruction already exists for this ship and cargo. Cancel it before adding another.",
      instruction_cargo_invalid: "Choose compatible cargo with a market at the visit port.",
      instruction_quantity_invalid: "Use 1–10,000 lots and a valid nonnegative limit price.",
      instruction_sell_exceeds_cargo:
        "The sell target exceeds the selected cargo currently aboard. Reduce the target and try again.",
      instruction_onward_invalid: "Choose an onward destination different from the visit port.",
      instruction_auto_depart_invalid: "Choose whether this visit should depart automatically.",
      instruction_onward_conflict:
        "All buy instructions at this visit must share one onward port. Update the shared onward destination first.",
      instruction_budget_invalid:
        "Buy instructions need a positive spending cap and a different onward port.",
      instruction_limit_reached:
        "This ship already has 20 active instructions. Cancel one before adding another.",
      instruction_not_active:
        "That instruction is no longer active or does not belong to your company.",
      invalid_command_payload: "The command payload must be an object.",
      too_many_command_fields: "The command contains too many fields (maximum 12).",
      command_payload_too_large: "The command payload is too large (maximum 4096 bytes).",
      invalid_session: "Your session is invalid or has expired. Please sign in again.",
      internal_error: "The world paused after an internal error. Please contact the operator.",
      market_busy: "The market is changing quickly. Please try again.",
      storage_unavailable: "The database is unavailable. Please try again later.",
      insufficient_cash: "Not enough available cash. Check reserved fuel and unpaid costs.",
      capacity_exceeded: "That cargo exceeds this ship's weight or volume limit.",
      incompatible_cargo:
        "This ship cannot carry that cargo, or its tank already holds a different liquid.",
      price_changed: "The market price changed. Review the latest quote and try again.",
      insufficient_supply: "There is not enough supply at that price.",
      insufficient_demand: "This port cannot buy that quantity right now.",
      insufficient_cargo: "You do not own that much cargo aboard this ship.",
      invalid_trade:
        "Choose a docked ship and an available cargo with a positive whole-lot quantity.",
      name_taken: "That company name is already taken.",
      invalid_name: "Use a company name between 1 and 60 characters.",
      no_invitation_quota: "No invitation entitlement is available.",
      departure_ship_unavailable: "Select a ship owned by your company before departing.",
      departure_destination_invalid: "Choose a valid destination port.",
      purchase_destination_required:
        "Choose a purchase destination in the voyage selector before buying cargo. It must have a valid route within the 24-hour voyage limit.",
      departure_fuel_limit_invalid:
        "The fuel limit is invalid. Review the voyage estimate and confirm again."
    }[reason] || "The action could not be completed. Please refresh and try again."
  end

  @doc false
  def ship_coordinates(ship, clock, catalogue) do
    if ship["status"] == "sailing" do
      # A removed route must not break rendering an already committed voyage.
      # Keep the marker at its departure port until arrival if geometry is absent.
      coords =
        get_in(catalogue, ["routes", ship["port"] <> "|" <> ship["destination"], "coordinates"]) ||
          List.duplicate(catalogue["ports"][ship["port"]]["coordinates"], 2)

      fraction =
        min(1, max(0, (clock - ship["depart_ms"]) / (ship["arrive_ms"] - ship["depart_ms"])))

      legs = Enum.chunk_every(coords, 2, 1, :discard)
      lengths = Enum.map(legs, fn [a, b] -> distance(a, b) end)
      target = Enum.sum(lengths) * fraction

      {point, _} =
        Enum.zip(legs, lengths)
        |> Enum.reduce_while({List.last(coords), target}, fn {[a, b], length}, {_, remaining} ->
          if remaining <= length and length > 0 do
            [x1, y1] = a
            [x2, y2] = b
            [dx, _] = normalize([x2 - x1, 0])
            ratio = remaining / length
            {:halt, {[x1 + dx * ratio, y1 + (y2 - y1) * ratio], 0}}
          else
            {:cont, {b, remaining - length}}
          end
        end)

      normalize(point)
    else
      catalogue["ports"][ship["port"]]["coordinates"]
    end
  end

  def distance([x1, y1], [x2, y2]) do
    rad = :math.pi() / 180

    a =
      :math.pow(:math.sin((y2 - y1) * rad / 2), 2) +
        :math.cos(y1 * rad) * :math.cos(y2 * rad) * :math.pow(:math.sin((x2 - x1) * rad / 2), 2)

    2 * :math.asin(:math.sqrt(min(1, a)))
  end

  def normalize([lon, lat]), do: [lon - 360 * :math.floor((lon + 180) / 360), lat]
end
