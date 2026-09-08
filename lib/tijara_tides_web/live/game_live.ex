defmodule TijaraTidesWeb.GameLive do
  use TijaraTidesWeb, :live_view
  alias TijaraTides.Infrastructure.GameServer
  alias TijaraTidesWeb.WorldMap

  @impl true
  def mount(_params, session, socket) do
    token = session["account_token"]

    if connected?(socket) do
      :ok = GameServer.subscribe()

      if token do
        GameServer.connect(token)
        Process.send_after(self(), :world_heartbeat, 15_000)
      end
    end

    socket =
      assign(socket,
        token: token,
        page_title: "Your shipping company",
        definitions: GameServer.definitions(),
        selected_port: "Singapore",
        map_region: nil,
        map_filters_open: false,
        map_ship_classes: MapSet.new(Map.keys(GameServer.definitions().classes)),
        map_show_others: true,
        traffic_grouping: "status",
        selected_ship: nil,
        inspected_ship: nil,
        trade_quantities: %{},
        trade_edited: MapSet.new(),
        purchase_good: nil,
        fleet_status: "all",
        port_market_side: "buy",
        trade_limits: %{},
        trade_context: nil,
        manifest_sort: {"good", :asc},
        market_good: "Lumber",
        cargo_menu_open: false,
        cargo_sort_roi: false,
        market_sort: %{"supply" => {"ask", :asc}, "demand" => {"bid", :desc}},
        company_draft: %{"name" => "", "port" => "Singapore", "package" => "general"},
        destination: nil,
        invite_code: nil,
        request_id: GameServer.request_id(),
        preview: nil
      )

    {:ok, refresh(socket)}
  end

  @impl true
  def handle_info({:game_changed, _revision}, socket), do: {:noreply, refresh(socket)}

  def handle_info(:world_heartbeat, socket) do
    GameServer.connect(socket.assigns.token)
    Process.send_after(self(), :world_heartbeat, 15_000)
    {:noreply, refresh(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_event("port", %{"id" => id}, socket) do
    if socket.assigns.definitions.catalogue["ports"][id],
      do: {:noreply, assign(socket, :selected_port, id)},
      else: {:noreply, socket}
  end

  def handle_event("map-region", %{"id" => region}, socket) do
    if socket.assigns.definitions.catalogue["clusters"][region],
      do: {:noreply, assign(socket, :map_region, region)},
      else: {:noreply, socket}
  end

  def handle_event("map-world", _params, socket), do: {:noreply, assign(socket, :map_region, nil)}

  def handle_event("toggle-map-filters", _params, socket) do
    {:noreply, assign(socket, :map_filters_open, !socket.assigns.map_filters_open)}
  end

  def handle_event("map-filters", params, socket) do
    classes =
      params
      |> Map.get("classes", [])
      |> List.wrap()
      |> Enum.filter(&Map.has_key?(socket.assigns.definitions.classes, &1))
      |> MapSet.new()

    {:noreply,
     assign(socket,
       map_ship_classes: classes,
       map_show_others: is_nil(socket.assigns.view.private) or params["show_others"] == "true"
     )}
  end

  def handle_event("traffic-grouping", %{"grouping" => grouping}, socket)
      when grouping in ["status", "company", "kind"] do
    {:noreply, assign(socket, :traffic_grouping, grouping)}
  end

  def handle_event("cargo-sort-roi", params, socket) do
    {:noreply, assign(socket, :cargo_sort_roi, params["roi"] == "true")}
  end

  def handle_event("toggle-cargo-menu", _params, socket) do
    {:noreply, assign(socket, :cargo_menu_open, !socket.assigns.cargo_menu_open)}
  end

  def handle_event("close-cargo-menu", _params, socket) do
    {:noreply, assign(socket, :cargo_menu_open, false)}
  end

  def handle_event("market-good", %{"good" => good}, socket) do
    if socket.assigns.definitions.catalogue["goods"][good],
      do: {:noreply, assign(socket, market_good: good, cargo_menu_open: false)},
      else: {:noreply, socket}
  end

  def handle_event("fleet-status", %{"status" => status}, socket)
      when status in ["all", "docked", "loading", "unloading", "sailing"] do
    {:noreply, assign(socket, :fleet_status, status)}
  end

  def handle_event("port-market-side", %{"side" => side}, socket) when side in ["buy", "sell"] do
    {:noreply, assign(socket, :port_market_side, side)}
  end

  def handle_event("sort-markets", %{"column" => column, "side" => side}, socket)
      when side in ["supply", "demand"] and
             column in ["port", "stock", "demand", "ask", "bid", "distance"] do
    direction = if socket.assigns.market_sort[side] == {column, :asc}, do: :desc, else: :asc

    {:noreply,
     assign(socket, :market_sort, Map.put(socket.assigns.market_sort, side, {column, direction}))}
  end

  def handle_event("sort-manifest", %{"column" => column}, socket)
      when column in ["good", "quantity", "weight", "volume", "average_cost", "expires_ms"] do
    direction = if socket.assigns.manifest_sort == {column, :asc}, do: :desc, else: :asc
    {:noreply, assign(socket, :manifest_sort, {column, direction})}
  end

  def handle_event("inspect-ship", %{"id" => id}, socket) do
    cond do
      socket.assigns.view.private && socket.assigns.view.private["ships"][id] ->
        handle_event("ship", %{"id" => id}, socket)

      socket.assigns.view.public["ships"][id] ->
        {:noreply, assign(socket, :inspected_ship, id)}

      true ->
        {:noreply, socket}
    end
  end

  def handle_event("ship", %{"id" => id}, socket) do
    own = socket.assigns.view.private && socket.assigns.view.private["ships"][id]

    if own do
      {:noreply,
       socket
       |> assign(selected_ship: id, selected_port: own["port"], inspected_ship: id, preview: nil)
       |> refresh()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("company-preview", params, socket) do
    if socket.assigns.definitions.catalogue["ports"][params["port"]] do
      draft = Map.take(params, ["name", "port", "package"])
      {:noreply, assign(socket, company_draft: draft, selected_port: params["port"])}
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "trade-preview",
        %{"action" => side, "good" => good, "quantity" => quantity},
        socket
      )
      when side in ["buy", "sell"] do
    if socket.assigns.definitions.catalogue["goods"][good] do
      quantities =
        Map.put(
          socket.assigns.trade_quantities,
          {side, good},
          bounded_quantity(
            integer(quantity),
            Map.get(socket.assigns.trade_limits, {side, good}, 0)
          )
        )

      socket =
        assign(socket,
          trade_quantities: quantities,
          trade_edited: MapSet.put(socket.assigns.trade_edited, {side, good})
        )

      {:noreply, if(side == "buy", do: assign(socket, :purchase_good, good), else: socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("company", params, socket),
    do: run(socket, Map.put(params, "action", "company"))

  def handle_event("invite", params, socket), do: run(socket, Map.put(params, "action", "invite"))

  def handle_event("trade", params, socket) do
    params =
      params
      |> Map.put("ship", socket.assigns.selected_ship)
      |> Map.put("destination", socket.assigns.destination)
      |> Map.update("quantity", 0, &integer/1)
      |> Map.update("limit", 0, &integer/1)

    run(socket, params)
  end

  def handle_event("preview", %{"destination" => dest}, socket) do
    preview = GameServer.preview(socket.assigns.token, socket.assigns.selected_ship, dest)
    socket = assign(socket, destination: dest, preview: preview)

    socket =
      if is_binary(dest) && socket.assigns.definitions.catalogue["ports"][dest] &&
           socket.assigns.ship do
        socket
        |> assign(selected_port: socket.assigns.ship["port"], port_market_side: "buy")
        |> push_event("workspace-panel", %{panel: 0})
      else
        socket
      end

    {:noreply, refresh(socket)}
  end

  def handle_event("sail", params, %{assigns: %{preview: %{"fuel" => fuel}}} = socket) do
    run(socket, %{
      "action" => "sail",
      "ship" => socket.assigns.selected_ship,
      "destination" => socket.assigns.destination,
      "request_id" => params["request_id"] || socket.assigns.request_id,
      "fuel_limit" => fuel
    })
  end

  def handle_event("port-destination", _params, socket) do
    ship = socket.assigns.ship
    destination = socket.assigns.selected_port

    if ship && ship["status"] == "docked" && ship["port"] != destination do
      case GameServer.preview(socket.assigns.token, ship["id"], destination) do
        nil ->
          {:noreply, put_flash(socket, :error, "No voyage is available to this port right now.")}

        preview ->
          {:noreply, socket |> assign(destination: destination, preview: preview) |> refresh()}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp run(socket, command) do
    {request, command} = Map.pop(command, "request_id", socket.assigns.request_id)

    case GameServer.command(socket.assigns.token, request, command) do
      {:ok, result} ->
        socket = if result["code"], do: assign(socket, :invite_code, result["code"]), else: socket

        socket =
          if command["action"] in ["buy", "sell"],
            do: assign(socket, trade_quantities: %{}, trade_edited: MapSet.new()),
            else: socket

        socket =
          if command["action"] == "company",
            do: assign(socket, :selected_port, command["port"]),
            else: socket

        {:noreply,
         socket
         |> assign(preview: nil, request_id: GameServer.request_id())
         |> put_flash(:info, "Done.")
         |> refresh()}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, error_message(reason)) |> refresh()}
    end
  end

  defp refresh(socket) do
    view = GameServer.snapshot(socket.assigns.token)

    ship =
      if view.private do
        view.private["ships"][socket.assigns.selected_ship] ||
          view.private["ships"]
          |> Map.values()
          |> Enum.sort_by(
            &{if(&1["status"] == "docked" && &1["cargo"] == [], do: 0, else: 1), &1["id"]}
          )
          |> List.first()
      end

    preview =
      if socket.assigns.destination not in [nil, ""] && ship && ship["status"] == "docked",
        do: GameServer.preview(socket.assigns.token, ship["id"], socket.assigns.destination)

    socket =
      if ship && is_nil(socket.assigns.selected_ship),
        do: assign(socket, :selected_port, ship["port"]),
        else: socket

    limits = GameServer.trade_limits(view, ship, socket.assigns.destination)
    context = {ship && ship["id"], ship && ship["port"], socket.assigns.destination}

    previous =
      if context == socket.assigns.trade_context, do: socket.assigns.trade_quantities, else: %{}

    edited =
      if context == socket.assigns.trade_context,
        do: socket.assigns.trade_edited,
        else: MapSet.new()

    quantities =
      Map.new(
        for {key, maximum} <- limits, maximum > 0 do
          quantity =
            if MapSet.member?(edited, key), do: Map.get(previous, key, maximum), else: maximum

          {key, bounded_quantity(quantity, maximum)}
        end
      )

    assign(socket,
      view: view,
      selected_ship: ship && ship["id"],
      ship: ship,
      preview: preview,
      trade_limits: limits,
      trade_edited: edited,
      trade_quantities: quantities,
      trade_context: context
    )
  end

  defp bounded_quantity(_quantity, maximum) when maximum < 1, do: 0
  defp bounded_quantity(quantity, maximum), do: max(1, min(quantity, maximum))

  defp owns_ship_at_port?(nil, _port), do: false

  defp owns_ship_at_port?(private, port) do
    Enum.any?(private["ships"], fn {_, ship} ->
      ship["port"] == port and ship["status"] != "sailing"
    end)
  end

  # Keep persisted good IDs stable when their player-facing names change.
  defp cargo_name(good), do: GameServer.cargo_name(good)

  defp route_distance(definitions, ship, destination) do
    if ship && ship["status"] == "docked" do
      if ship["port"] == destination,
        do: 0,
        else:
          get_in(definitions.catalogue, [
            "routes",
            ship["port"] <> "|" <> destination,
            "nautical_miles"
          ])
    end
  end

  defp cargo_markets(_definitions, _view, nil, _side, _sort, _ship), do: []

  defp cargo_markets(definitions, view, good, side, {column, direction}, ship) do
    rows =
      for {port, definition} <- definitions.catalogue["ports"],
          String.contains?(
            definition["roles"][good],
            if(side == "supply", do: "exp", else: "imp")
          ),
          quote = view.markets[port <> "|" <> good],
          quote["manual"],
          quote[if(side == "supply", do: "stock", else: "demand")] > 0,
          do:
            Map.merge(quote, %{
              "port" => port,
              "distance" => route_distance(definitions, ship, port)
            })

    if column in ["ask", "bid"] do
      quantity_key = if side == "supply", do: "stock", else: "demand"

      Enum.sort_by(rows, fn quote ->
        price = if direction == :asc, do: quote[column], else: -quote[column]

        {price, -quote[quantity_key],
         if(side == "demand", do: quote["distance"] || 1_000_000_000, else: 0), quote["port"]}
      end)
    else
      {known, unknown} = Enum.split_with(rows, &(not is_nil(&1[column])))

      Enum.sort_by(known, &{&1[column], &1["port"]}, direction) ++
        Enum.sort_by(unknown, & &1["port"])
    end
  end

  defp cargo_roi(nil), do: "—"
  defp cargo_roi(roi), do: :erlang.float_to_binary(roi * 100, decimals: 2) <> "%"

  defp cargo_price_range(definitions, view, good) do
    ask = List.first(cargo_markets(definitions, view, good, "supply", {"ask", :asc}, nil))
    bid = List.first(cargo_markets(definitions, view, good, "demand", {"bid", :desc}, nil))

    if bid || ask do
      %{
        label:
          "bid #{if bid, do: money(bid["bid"]), else: "—"} / " <>
            "ask #{if ask, do: money(ask["ask"]), else: "—"}",
        roi: if(bid && ask && ask["ask"] > 0, do: (bid["bid"] - ask["ask"]) / ask["ask"])
      }
    end
  end

  defp visible_market_rows(definitions, view, ship, port) do
    definitions.catalogue["goods"]
    |> Enum.sort_by(fn {good, _} -> cargo_name(good) end)
    |> Enum.filter(fn {good, _item} ->
      quote = view.markets[port <> "|" <> good]

      # Handling does not turn a local market into a remote-port preview.
      quote["manual"] and
        (is_nil(ship) or good in view.private["compatible_cargo"][ship["id"]]) and
        if ship && ship["port"] == port && ship["status"] != "sailing" do
          available_to_trade("buy", quote, ship, good) > 0 or
            available_to_trade("sell", quote, ship, good) > 0
        else
          quote["stock"] > 0 or quote["demand"] > 0
        end
    end)
  end

  defp available_to_trade("buy", quote, _ship, _good), do: quote["stock"]

  defp available_to_trade("sell", quote, ship, good),
    do: min(cargo_aboard(ship, good), quote["demand"])

  defp cargo_aboard(ship, good) do
    (ship["cargo"] || [])
    |> Enum.filter(&(&1["good"] == good))
    |> Enum.map(& &1["quantity"])
    |> Enum.sum()
  end

  defp sorted_manifest(cargo, goods, {column, direction}) do
    rows = manifest(cargo)
    # Non-perishable cargo always follows dated cargo when sorting by expiry.
    {undated, dated} =
      Enum.split_with(rows, &(column == "expires_ms" && is_nil(&1["expires_ms"])))

    Enum.sort_by(
      dated,
      fn row ->
        value =
          case column do
            "good" -> cargo_name(row["good"])
            "weight" -> row["quantity"] * goods[row["good"]]["weight_kg"]
            "volume" -> row["quantity"] * goods[row["good"]]["volume_l"]
            _ -> row[column]
          end

        {value, cargo_name(row["good"])}
      end,
      direction
    ) ++ undated
  end

  defp manifest(cargo) do
    cargo
    |> Enum.group_by(& &1["good"])
    |> Enum.sort_by(fn {good, _} -> cargo_name(good) end)
    |> Enum.map(fn {good, batches} ->
      quantity = Enum.sum(Enum.map(batches, & &1["quantity"]))
      cost = Enum.sum(Enum.map(batches, &(&1["quantity"] * &1["unit_cost"])))
      expiries = batches |> Enum.map(& &1["expires_ms"]) |> Enum.reject(&is_nil/1)

      %{
        "good" => good,
        "quantity" => quantity,
        "average_cost" => cost / quantity,
        "expires_ms" => Enum.min(expiries, fn -> nil end)
      }
    end)
  end

  defp cubic_meters(litres) do
    whole = Integer.to_string(div(litres, 1000))

    fraction =
      rem(litres, 1000)
      |> Integer.to_string()
      |> String.pad_leading(3, "0")
      |> String.trim_trailing("0")

    whole <> if(fraction == "", do: "", else: "." <> fraction) <> " m³"
  end

  defp cargo_volume(item, quantity) do
    litres = item["volume_l"] * quantity
    if item["hold"] == "liquid", do: "#{litres} L", else: cubic_meters(litres)
  end

  attr :estimates, :list, required: true

  defp voyage_freshness(assigns) do
    ~H"""
    <div :if={@estimates != []} class="voyage-freshness mt-3 w-full text-sm text-amber-200">
      <p :for={estimate <- @estimates}>
        {cargo_name(estimate["good"])}: estimated time to first expiry — {minutes(
          estimate["arrival_ms"]
        )} min at arrival; {minutes(estimate["unloaded_ms"])} min after unloading.
        <strong :if={estimate["unloaded_ms"] == 0}>Spoilage expected before unloading finishes.</strong>
      </p>
      <p class="text-xs">
        Assumes unloading all current cargo. Estimates update with the voyage and may change with delays.
      </p>
    </div>
    """
  end

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> -1
    end
  end

  defp integer(_), do: -1
  defp dollars(whole), do: "$" <> Integer.to_string(whole)
  defp money(cents), do: dollars(round(cents / 100))
  defp minutes(ms), do: Float.round(ms / 60000, 1)

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
      internal_error: "The world paused after an internal error. Please contact the operator.",
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

  defp distance([x1, y1], [x2, y2]) do
    rad = :math.pi() / 180

    a =
      :math.pow(:math.sin((y2 - y1) * rad / 2), 2) +
        :math.cos(y1 * rad) * :math.cos(y2 * rad) * :math.pow(:math.sin((x2 - x1) * rad / 2), 2)

    2 * :math.asin(:math.sqrt(min(1, a)))
  end

  defp normalize([lon, lat]), do: [lon - 360 * :math.floor((lon + 180) / 360), lat]

  @impl true
  def render(assigns) do
    map_ships =
      Enum.filter((assigns.view.public && assigns.view.public["ships"]) || %{}, fn {id, ship} ->
        ship["status"] == "sailing" and
          MapSet.member?(assigns.map_ship_classes, ship["class"]) and
          (assigns.map_show_others or is_nil(assigns.view.private) or
             Map.has_key?(assigns.view.private["ships"], id))
      end)

    cargo_options =
      for {good, _} <-
            Enum.sort_by(assigns.definitions.catalogue["goods"], fn {good, _} ->
              cargo_name(good)
            end),
          range = cargo_price_range(assigns.definitions, assigns.view, good),
          do: {good, range}

    cargo_options =
      if assigns.cargo_sort_roi do
        Enum.sort_by(cargo_options, fn {good, quote} ->
          {is_nil(quote.roi), -(quote.roi || 0), cargo_name(good)}
        end)
      else
        cargo_options
      end

    market_good =
      if Enum.any?(cargo_options, fn {good, _} -> good == assigns.market_good end) do
        assigns.market_good
      else
        case List.first(cargo_options) do
          {good, _} -> good
          nil -> nil
        end
      end

    assigns =
      assign(assigns,
        map_ships: map_ships,
        cargo_options: cargo_options,
        cargo_roi_varies:
          cargo_options |> Enum.map(fn {_, quote} -> quote.roi end) |> Enum.uniq() |> length() > 1,
        market_good: market_good
      )

    ~H"""
    <Layouts.app flash={@flash}>
      <main class={[
        "game-screen text-slate-100",
        @view.private && @view.private["company"] && "game-screen-playing"
      ]}>
        <header class="game-header flex items-center justify-between gap-3">
          <div>
            <a href="/" class="text-sm text-teal-300">Tijara Tides</a><h1 class="game-tagline text-sm font-semibold">
              Build a company. Trade the world.
            </h1>
          </div>
        </header>
        <div
          :if={@view.status != :ready}
          id="game-unavailable"
          class="rounded-xl border border-amber-700 bg-slate-900 p-8"
        >
          <h2 class="text-xl">The trading world is not available yet</h2>
          <p class="mt-3">
            The lobby is open. The operator must configure game storage and apply its migrations before companies can begin trading.
          </p>
          <a href="/" class="mt-4 inline-block underline">Return to lobby</a>
        </div>
        <div :if={@view.status == :ready} class="game-body">
          <section
            :if={!@view.private}
            class="mb-6 rounded-xl border border-slate-700 bg-slate-900 p-6"
          >
            <h2 class="text-xl">Start with an invitation</h2>
            <p class="my-3 text-slate-300">
              You can explore the world without an account. Redeem a shareable invitation to establish your company on this device.
            </p>
            <.form for={%{}} action={~p"/session/redeem"} class="flex flex-wrap gap-3">
              <input
                name="code"
                required
                maxlength="100"
                placeholder="Invitation code"
                aria-label="Invitation code"
                autocomplete="off"
                size="48"
                class="min-w-0 w-full max-w-lg rounded bg-slate-800 px-4 py-2"
              />
              <button class="rounded bg-teal-600 px-4 py-2">Redeem invitation</button>
            </.form>
          </section>
          <section
            :if={@view.private && !@view.private["company"]}
            class="mb-6 rounded-xl border border-slate-700 bg-slate-900 p-6"
          >
            <h2 class="text-xl">Name your company and choose a home port</h2>
            <p class="my-3 text-slate-300">
              Every package has three ships and $200,000 in combined fleet value and cash. Explore port markets below before choosing.
            </p>
            <.form
              for={%{}}
              id="company-form"
              phx-submit="company"
              phx-change="company-preview"
              class="flex flex-wrap gap-3"
            >
              <input type="hidden" name="request_id" value={@request_id} />
              <input
                name="name"
                value={@company_draft["name"]}
                required
                maxlength="60"
                placeholder="Company name"
                aria-label="Company name"
                class="rounded bg-slate-800 px-3 py-2"
              />
              <select name="port" aria-label="Home port" class="rounded bg-slate-800 px-3 py-2"><option
                :for={name <- Enum.sort(Map.keys(@definitions.catalogue["ports"]))}
                value={name}
                selected={name == @company_draft["port"]}
              >
                {name}
              </option></select>
              <select name="package" aria-label="Starter fleet" class="rounded bg-slate-800 px-3 py-2"><option
                :for={{id, ships} <- Enum.sort(@definitions.packages)}
                value={id}
                selected={id == @company_draft["package"]}
              >
                {id} · {Enum.join(ships, ", ")} · {money(@definitions.package_cash[id])} cash
              </option></select>
              <button class="rounded bg-teal-600 px-4 py-2">Establish company</button>
            </.form>
          </section>
          <details :if={@view.private} id="company-menu" class="company-menu">
            <summary>Account &amp; invitations</summary>
            <div class="company-menu-body">
              <p class="text-sm text-amber-100">
                Keep this device session: identity linking is not included in this first milestone. Losing the session permanently loses access to this account. Invitations cannot be reused to sign in.
              </p>
              <section class="my-6 rounded-xl bg-slate-900 p-5">
                <h2 class="text-xl">Invitations & notices</h2><p class="my-2">
                  Available entitlements: {@view.private["account"]["invite_quota"]}
                </p>
                <button
                  phx-click="invite"
                  phx-value-request_id={@request_id}
                  class="rounded border border-teal-700 px-4 py-2"
                >Generate shareable invitation</button>
                <p :if={@invite_code} class="mt-3 break-all font-mono text-teal-200">
                  {@invite_code}
                </p>
                <p :for={notice <- @view.private["notices"]} class="mt-3">{notice["text"]}</p>
              </section>
            </div>
          </details>
          <section
            :if={@view.private && @view.private["company"]}
            class="company-summary"
          >
            <div>
              <h2 class="text-2xl">{@view.private["company"]["name"]}</h2><p class="text-slate-400">
                Home: {@view.private["company"]["home"]}
              </p>
            </div>
            <div>
              Available cash<p class="text-2xl">
                {money(@view.private["company"]["cash"] - @view.private["company"]["reserved"])}
              </p>
            </div>
            <div>
              Reserved fuel<p class="text-2xl">{money(@view.private["company"]["reserved"])}</p>
            </div>
            <div>
              Trading result<p class="text-2xl">{money(@view.private["company"]["profit"])}</p><p
                :if={@view.private["company"]["unpaid"] > 0}
                class="text-amber-300"
              >
                Unpaid: {money(@view.private["company"]["unpaid"])}
              </p>
            </div>
          </section>
          <div id="game-workspace" phx-hook="Workspace" class="game-workspace">
            <nav class="workspace-tabs" aria-label="Game panels">
              <button type="button" data-panel="0" aria-controls="ports-panel" aria-current="false">Ports</button>
              <button type="button" data-panel="1" aria-controls="ships-panel" aria-current="true">Ships</button>
              <button type="button" data-panel="2" aria-controls="cargo-panel" aria-current="false">Cargo</button>
            </nav>
            <div class="workspace-panels">
              <section id="ports-panel" class="workspace-panel" aria-label="Ports">
                <h2 class="panel-title">Ports</h2>
                <div class="panel-content" tabindex="0" aria-label="Port details and trading">
                  <section class="my-6 rounded-xl border border-slate-700 p-5">
                    <div class="flex flex-wrap justify-between gap-3">
                      <h2 class="text-2xl">{@selected_port}</h2><form
                        id="port-selector"
                        phx-change="port"
                      >
                        <select
                          aria-label="Inspect port"
                          name="id"
                          class="rounded bg-slate-800 px-3 py-2"
                        ><option
                          :for={name <- Enum.sort(Map.keys(@definitions.catalogue["ports"]))}
                          value={name}
                          selected={name == @selected_port}
                        >
                          {name}
                        </option></select>
                      </form>
                    </div>
                    <button
                      :if={@ship && @ship["status"] == "docked" && @ship["port"] != @selected_port}
                      id="set-port-destination"
                      type="button"
                      phx-click="port-destination"
                      disabled={@destination == @selected_port}
                      title={"Set #{@selected_port} as the destination for #{@ship["name"]}"}
                      class="my-2 rounded border border-teal-700 px-3 py-2 text-sm text-teal-200 disabled:opacity-60"
                    >
                      {if @destination == @selected_port,
                        do: "Selected destination",
                        else: "Set as destination"}
                    </button>
                    <details class="my-2 text-sm text-slate-400">
                      <summary class="cursor-pointer">About this port</summary>
                      <p class="mt-2">
                        {@definitions.catalogue["ports"][@selected_port]["identity"]}
                      </p>
                    </details>
                    <section
                      :if={@ship && @ship["status"] == "docked" && @ship["port"] != @selected_port}
                      id="destination-planner"
                      class="my-3 rounded border border-teal-900 p-2"
                    >
                      <% distance = route_distance(@definitions, @ship, @selected_port) %>
                      <h3 class="text-sm text-teal-200">
                        From {@ship["port"]} · {if distance,
                          do: "#{round(distance)} nautical miles",
                          else: "No route available"}
                      </h3>
                      <p class="my-2 text-xs text-slate-400">
                        Cargo available at {@ship["port"]}. Profit estimates use the listed load, current prices, handling, cleaning, fuel, canals, and estimated fleet upkeep. Cash affordability and spoilage are not included; prices and demand can change.
                      </p>
                      <% options =
                        GameServer.destination_options(@definitions, @view, @ship, @selected_port) %>
                      <p :if={options == []} class="text-sm text-slate-400">
                        No compatible cargo available at the current port.
                      </p>
                      <table
                        :if={options != []}
                        class="w-full text-xs"
                        aria-label="Destination trade opportunities"
                      >
                        <thead>
                          <tr>
                            <th>Cargo / supply</th><th>Buy / lot</th><th>Bid / demand</th><th>
                              Load / est. profit
                            </th>
                          </tr>
                        </thead>
                        <tbody>
                          <tr
                            :for={option <- options}
                            data-good={option.good}
                            class="border-t border-slate-700"
                          >
                            <td>
                              <button
                                type="button"
                                phx-click="market-good"
                                phx-value-good={option.good}
                                class="text-left text-teal-300 underline"
                              >{cargo_name(option.good)}</button><p>
                                {option.source["stock"]} lots · {cargo_volume(
                                  option.item,
                                  option.source["stock"]
                                )}
                              </p>
                            </td>
                            <td>{money(option.source["ask"])}</td>
                            <td>
                              {if option.demand > 0,
                                do: "#{money(option.buyer["bid"])} / #{option.demand}",
                                else: "No demand"}
                            </td>
                            <td>
                              {option.lots} lots<p class={
                                if option.profit && option.profit >= 0,
                                  do: "text-teal-300",
                                  else: "text-red-400"
                              }>
                                {if is_nil(option.profit), do: "—", else: money(option.profit)}
                              </p>
                            </td>
                          </tr>
                        </tbody>
                      </table>
                    </section>
                    <TijaraTidesWeb.PortTraffic.traffic
                      public={@view.public}
                      classes={@definitions.classes}
                      port={@selected_port}
                      grouping={@traffic_grouping}
                    />
                    <p class="mb-3 text-sm text-slate-400">
                      Whole lots · finite local supply and demand · trades require your selected ship to be docked here. Handling takes time.
                    </p>
                    <div class="mb-3 flex gap-2" role="group" aria-label="Port market side">
                      <button
                        :for={{side, label} <- [{"buy", "Buy / supply"}, {"sell", "Sell / demand"}]}
                        type="button"
                        phx-click="port-market-side"
                        phx-value-side={side}
                        aria-pressed={to_string(@port_market_side == side)}
                        class={[
                          "flex-1 rounded px-3 py-2 text-sm",
                          if(@port_market_side == side,
                            do: "bg-teal-800 text-teal-100",
                            else: "bg-slate-800 text-slate-400"
                          )
                        ]}
                      >{label}</button>
                    </div>
                    <% market_rows =
                      visible_market_rows(@definitions, @view, @ship, @selected_port)
                      |> Enum.filter(fn {good, _} ->
                        quote = @view.markets[@selected_port <> "|" <> good]
                        quote[if(@port_market_side == "buy", do: "stock", else: "demand")] > 0
                      end) %>
                    <% show_ship_columns = owns_ship_at_port?(@view.private, @selected_port) %>
                    <% selected_ship_here =
                      @ship && @ship["port"] == @selected_port && @ship["status"] != "sailing" %>
                    <% compare_destination =
                      @port_market_side == "buy" && selected_ship_here && is_binary(@destination) &&
                        @destination != @selected_port &&
                        @definitions.catalogue["ports"][@destination] %>
                    <p
                      :if={compare_destination}
                      id="destination-market-note"
                      class="mb-3 text-xs text-slate-400"
                    >
                      Destination bids: {@destination}. Spread is per lot before handling and voyage costs; demand and prices may change before arrival.
                    </p>
                    <% purchase =
                      if @port_market_side == "buy" && selected_ship_here &&
                           @ship["status"] == "docked" do
                        options =
                          Enum.filter(market_rows, fn {good, item} ->
                            item["manual"] && Map.get(@trade_quantities, {"buy", good}, 0) > 0
                          end)

                        Enum.find(options, fn {good, _} -> good == @purchase_good end) ||
                          List.first(options)
                      end %>
                    <%= if purchase do %>
                      <% {good, item} = purchase %>
                      <% quantity = Map.get(@trade_quantities, {"buy", good}, 0) %>
                      <% voyage =
                        GameServer.purchase_voyage(
                          @ship,
                          item,
                          quantity,
                          @destination,
                          @view.private["ships"],
                          @view.public["clock_ms"]
                        ) %>
                      <p
                        :if={voyage}
                        id="purchase-voyage-summary"
                        class="mb-3 text-sm text-slate-300"
                        role="status"
                      >
                        For {quantity} lots of {cargo_name(good)}, keep {money(voyage["required"])} for {@destination}: fuel {money(
                          voyage["fuel"]
                        )}, canals {money(voyage["canal_fees"])}, estimated fleet upkeep {money(
                          voyage["upkeep"]
                        )} through loading and arrival.
                      </p>
                    <% end %>
                    <p
                      :if={
                        @port_market_side == "buy" && selected_ship_here &&
                          @ship["status"] == "docked" && !@preview
                      }
                      id="purchase-destination-reminder"
                      class="mb-3 text-sm text-amber-200"
                    >
                      Choose a valid destination in the Ships panel before buying.
                    </p>
                    <p :if={market_rows == []} class="py-4 text-slate-400">
                      No cargo is available to {@port_market_side} here right now.
                    </p>
                    <div :if={market_rows != []} class="overflow-x-auto">
                      <table
                        id="port-market-table"
                        class="w-full text-left text-sm"
                        aria-label={
                          if(@port_market_side == "buy", do: "Port supply", else: "Port demand")
                        }
                      >
                        <thead class="text-slate-400">
                          <tr>
                            <th class="cargo-description-column py-2">Cargo / lot size</th><th class="market-price-column">
                              {if @port_market_side == "buy",
                                do: "Buy / supply",
                                else: "Sell / demand"}
                            </th><th :if={show_ship_columns} class="aboard-column">
                              Aboard<br /><span class="font-normal">(lots)</span>
                            </th><th :if={show_ship_columns}>
                              Trade
                            </th>
                          </tr>
                        </thead><tbody>
                          <tr
                            :for={{good, item} <- market_rows}
                            class="border-t border-slate-800"
                          >
                            <% q = @view.markets[@selected_port <> "|" <> good] %>
                            <% destination_quote =
                              if compare_destination, do: @view.markets[@destination <> "|" <> good] %>
                            <td class="cargo-description-column py-3">
                              <button
                                type="button"
                                phx-click="market-good"
                                phx-value-good={good}
                                aria-label={"View markets for #{cargo_name(good)}"}
                                class="rounded text-left text-teal-300 underline decoration-teal-700 underline-offset-2 hover:text-teal-100 focus-visible:outline-2 focus-visible:outline-teal-300"
                              >{cargo_name(good)}</button>
                              <p class="text-xs text-slate-400">
                                {item["weight_kg"]} kg · {cargo_volume(item, 1)}
                                <span :if={q["manual"]}> · handling {money(q["handling_fee"])} / lot</span>
                              </p>
                            </td>
                            <td class="market-price-column">
                              {money(q[if(@port_market_side == "buy", do: "ask", else: "bid")])} / {q[
                                if(@port_market_side == "buy", do: "stock", else: "demand")
                              ]}
                              <div
                                :if={
                                  destination_quote && destination_quote["manual"] &&
                                    destination_quote["demand"] > 0
                                }
                                class="destination-bid mt-1 text-xs"
                                data-good={good}
                              >
                                <span class="block text-slate-300">{money(destination_quote["bid"])} bid</span>
                                <span class={
                                  if destination_quote["bid"] >= q["ask"],
                                    do: "text-teal-300",
                                    else: "text-red-400"
                                }>
                                  {if destination_quote["bid"] > q["ask"], do: "+"}{money(
                                    destination_quote["bid"] - q["ask"]
                                  )} spread
                                </span>
                                <span class="block text-slate-400">{destination_quote["demand"]} lots demand</span>
                              </div>
                            </td>
                            <td
                              :if={show_ship_columns}
                              id={"aboard-#{String.replace(good, " ", "-")}"}
                              class="aboard-column font-semibold text-teal-200"
                            >
                              {if selected_ship_here, do: cargo_aboard(@ship, good), else: "—"}
                            </td>
                            <td :if={show_ship_columns}>
                              <span :if={!q["manual"]} class="text-slate-500">Available in a later market milestone</span>
                              <.form
                                :for={side <- [@port_market_side]}
                                :if={
                                  q["manual"] && @ship && @ship["port"] == @selected_port &&
                                    @ship["status"] == "docked"
                                }
                                for={%{}}
                                id={"trade-#{side}-#{String.replace(good, " ", "-")}"}
                                phx-submit="trade"
                                phx-change="trade-preview"
                                class="trade-controls flex flex-wrap gap-2"
                                phx-hook="TradeQuantity"
                                data-quantity={Map.get(@trade_quantities, {side, good}, 0)}
                                data-max={Map.get(@trade_limits, {side, good}, 0)}
                              >
                                <% available = Map.get(@trade_limits, {side, good}, 0) %>
                                <% quantity =
                                  if available > 0,
                                    do: Map.get(@trade_quantities, {side, good}, available),
                                    else: 0 %>
                                <% freshness =
                                  GameServer.trade_freshness(
                                    q,
                                    @ship,
                                    side,
                                    good,
                                    quantity,
                                    @view.public["clock_ms"]
                                  ) %>
                                <input type="hidden" name="request_id" value={@request_id} />
                                <input type="hidden" name="action" value={side} /><input
                                  type="hidden"
                                  name="good"
                                  value={good}
                                /><input
                                  type="hidden"
                                  name="limit"
                                  value={if(side == "buy", do: q["ask"], else: q["bid"])}
                                />
                                <input
                                  type="range"
                                  name="quantity_slider"
                                  min={if available > 0, do: 1, else: 0}
                                  max={available}
                                  step="1"
                                  value={quantity}
                                  disabled={available < 1}
                                  aria-label={"#{String.capitalize(side)} #{cargo_name(good)} quantity slider"}
                                  class="w-full basis-full accent-teal-400"
                                />
                                <input
                                  type="number"
                                  id={"quantity-#{side}-#{String.replace(good, " ", "-")}"}
                                  name="quantity"
                                  min={if available > 0, do: 1, else: 0}
                                  max={max(0, min(10_000, available))}
                                  disabled={available <= 0}
                                  value={quantity}
                                  aria-label={"#{cargo_name(good)} quantity"}
                                  class="w-16 rounded bg-slate-800 px-2"
                                />
                                <button
                                  disabled={available <= 0}
                                  title={
                                    if available <= 0,
                                      do:
                                        if(side == "buy",
                                          do:
                                            "No feasible purchase: check destination, funds, stock, and capacity",
                                          else:
                                            "No feasible sale: check cargo, demand, and buyer funds"
                                        )
                                  }
                                  class="rounded bg-teal-700 px-3 py-1 disabled:cursor-not-allowed disabled:bg-slate-700 disabled:text-slate-400 disabled:opacity-60"
                                >{String.capitalize(side)}</button>
                                <%= if side == "buy" and available > 0 and quantity > 0 do %>
                                  <% total = GameServer.purchase_total(q, @ship, item, quantity) %>
                                  <% voyage =
                                    GameServer.purchase_voyage(
                                      @ship,
                                      item,
                                      quantity,
                                      @destination,
                                      @view.private["ships"],
                                      @view.public["clock_ms"]
                                    ) %>
                                  <% unaffordable =
                                    is_nil(voyage) or
                                      total + voyage["required"] >
                                        @view.private["company"]["cash"] -
                                          @view.private["company"]["reserved"] or
                                      @view.private["company"]["unpaid"] > 0 %>
                                  <span
                                    class={[
                                      "purchase-total self-center whitespace-nowrap text-sm tabular-nums",
                                      if(unaffordable, do: "text-red-400", else: "text-slate-300")
                                    ]}
                                    title={
                                      if unaffordable,
                                        do:
                                          "Choose a valid destination and leave enough cash for fuel, canal fees, and estimated fleet upkeep after purchasing. Includes handling and any tanker cleaning fee.",
                                        else: "Includes handling and any tanker cleaning fee."
                                    }
                                    role="status"
                                  >
                                    {money(total)} total<span :if={unaffordable} class="sr-only"> — insufficient available funds</span>
                                  </span>
                                <% end %>
                                <p
                                  :if={freshness && available > 0}
                                  class="w-full text-xs text-amber-200"
                                  role="status"
                                >
                                  {quantity} lots: first expiry in {minutes(freshness["remaining_ms"])} min now;
                                  estimated {minutes(freshness["after_ms"])} min remaining after {minutes(
                                    freshness["handling_ms"]
                                  )} min handling.
                                  <strong :if={freshness["after_ms"] == 0}>Expected to expire during handling.</strong>
                                  Estimates may change before settlement.
                                </p>
                              </.form>
                            </td>
                          </tr>
                        </tbody>
                      </table>
                    </div>
                  </section>
                </div>
              </section>
              <section id="ships-panel" class="workspace-panel" aria-label="Ships">
                <h2 class="panel-title">Ships</h2>
                <section
                  id="map-panel"
                  data-regional={to_string(not is_nil(@map_region))}
                  class="overflow-hidden rounded-xl border border-slate-700 bg-slate-950"
                >
                  <% viewport = WorldMap.viewport(@definitions.catalogue, @map_region) %>
                  <div class="map-toolbar px-3 py-2">
                    <button
                      id="map-expand"
                      type="button"
                      data-map-expand
                      aria-expanded="false"
                      aria-controls="map-panel"
                      class="map-expand rounded border border-slate-600 px-3 py-1 text-xs"
                    >
                      <span class="map-expand-label">Expand <span class="map-button-word">map ⛶</span></span>
                      <span class="map-restore-label">Restore main screen ↙</span>
                    </button>
                    <button
                      id="map-filter-toggle"
                      phx-click="toggle-map-filters"
                      aria-expanded={to_string(@map_filters_open)}
                      aria-controls="map-filters"
                      class="rounded border border-slate-600 px-3 py-1 text-xs"
                    >
                      Ship
                      <span class="map-button-word">filters {if @map_filters_open, do: "▴", else: "▾"}</span>
                    </button>
                    <form
                      :if={@map_filters_open}
                      id="map-filters"
                      phx-change="map-filters"
                      class="mt-2 rounded border border-slate-600 bg-slate-900 p-3 text-xs"
                    >
                      <fieldset>
                        <legend class="mb-2 text-slate-400">Ship types</legend>
                        <input type="hidden" name="classes[]" value="" />
                        <div class="grid grid-cols-2 gap-2">
                          <label
                            :for={
                              {id, ship_class} <-
                                Enum.sort_by(@definitions.classes, fn {_, c} -> c["name"] end)
                            }
                            class="flex items-center gap-2"
                          >
                            <input
                              type="checkbox"
                              name="classes[]"
                              value={id}
                              checked={MapSet.member?(@map_ship_classes, id)}
                            />
                            {ship_class["name"]}
                          </label>
                        </div>
                      </fieldset>
                      <label
                        :if={@view.private}
                        class="mt-3 flex items-center gap-2 border-t border-slate-700 pt-2"
                      >
                        <input type="hidden" name="show_others" value="false" />
                        <input
                          type="checkbox"
                          name="show_others"
                          value="true"
                          checked={@map_show_others}
                        /> Show other companies’ ships
                      </label>
                    </form>
                  </div>
                  <div
                    :if={@map_region}
                    class="map-region-heading flex items-center justify-between px-4 py-3"
                  >
                    <h2 class="text-lg">{@map_region}</h2>
                    <button phx-click="map-world" class="rounded border border-teal-700 px-3 py-2">World view</button>
                  </div>
                  <svg
                    id="world-map"
                    viewBox={viewport.box}
                    role="group"
                    aria-label="World ports and public ship positions on a Equal Earth map"
                    class="w-full"
                  >
                    <polygon
                      :for={
                        ring <- Map.get(@definitions.regional_land, @map_region, @definitions.land)
                      }
                      vector-effect="non-scaling-stroke"
                      points={WorldMap.points(ring)}
                      fill="#172f39"
                      stroke="#294551"
                      stroke-width="0.4"
                    />
                    <polyline
                      :for={lon <- -180..180//30}
                      vector-effect="non-scaling-stroke"
                      points={WorldMap.points(for lat <- -90..90//2, do: [lon, lat])}
                      fill="none"
                      stroke="#1e293b"
                    />
                    <polyline
                      :for={lat <- -60..60//30}
                      vector-effect="non-scaling-stroke"
                      points={WorldMap.points(for lon <- -180..180//2, do: [lon, lat])}
                      fill="none"
                      stroke="#1e293b"
                    />
                    <g :for={{id, s} <- @map_ships} data-map-route={id}>
                      <% route =
                        @definitions.catalogue["routes"][s["port"] <> "|" <> s["destination"]][
                          "coordinates"
                        ] %>
                      <path
                        vector-effect="non-scaling-stroke"
                        d={WorldMap.path(route)}
                        fill="none"
                        stroke="#155e75"
                        stroke-width="1"
                      />
                      <path
                        :for={arrow <- WorldMap.route_arrows(route, viewport.scale)}
                        d="M -4 -3 L 3 0 L -4 3"
                        transform={"translate(#{arrow.x} #{arrow.y}) rotate(#{arrow.angle}) scale(#{viewport.scale})"}
                        fill="none"
                        stroke="#38b8cf"
                        stroke-width="1.5"
                        vector-effect="non-scaling-stroke"
                        pointer-events="none"
                        aria-hidden="true"
                      />
                    </g>
                    <g
                      :for={marker <- WorldMap.markers(@definitions.catalogue, @map_region)}
                      role="button"
                      tabindex="0"
                      aria-label={
                        if length(marker.ports) > 1,
                          do: "#{marker.name}: #{length(marker.ports)} ports",
                          else: "Select #{marker.name}"
                      }
                      phx-click={if length(marker.ports) > 1, do: "map-region", else: "port"}
                      phx-keydown={if length(marker.ports) > 1, do: "map-region", else: "port"}
                      phx-key="Enter"
                      phx-value-id={marker.name}
                      class="cursor-pointer"
                    >
                      <circle
                        cx={hd(marker.center)}
                        cy={List.last(marker.center)}
                        r={16 * viewport.scale}
                        fill="transparent"
                      />
                      <circle
                        cx={hd(marker.center)}
                        cy={List.last(marker.center)}
                        r={
                          if(length(marker.ports) > 1,
                            do: 11,
                            else: if(marker.name == @selected_port, do: 7, else: 5)
                          ) * viewport.scale
                        }
                        class="port-marker-dot"
                        fill="#2dd4bf"
                        stroke="#0f172a"
                        vector-effect="non-scaling-stroke"
                      >
                        <title>
                          {marker.name} — {if length(marker.ports) > 1,
                            do: Enum.join(marker.ports, ", "),
                            else: @definitions.catalogue["ports"][marker.name]["harbor"]}
                        </title>
                      </circle>
                      <text
                        :if={@map_region}
                        data-port-label
                        data-label-x={hd(marker.center)}
                        data-label-y={List.last(marker.center)}
                        data-label-dx={WorldMap.label_position(marker.name).dx}
                        data-label-dy={WorldMap.label_position(marker.name).dy}
                        x={
                          hd(marker.center) + WorldMap.label_position(marker.name).dx * viewport.scale
                        }
                        y={
                          List.last(marker.center) +
                            WorldMap.label_position(marker.name).dy * viewport.scale
                        }
                        text-anchor={WorldMap.label_position(marker.name).anchor}
                        font-size={12 * viewport.scale}
                        fill="#e2e8f0"
                        stroke="#020617"
                        stroke-width={3 * viewport.scale}
                        paint-order="stroke"
                        pointer-events="none"
                      >
                        {marker.name}
                      </text>
                      <text
                        :if={length(marker.ports) > 1}
                        x={hd(marker.center)}
                        y={List.last(marker.center)}
                        text-anchor="middle"
                        dominant-baseline="central"
                        font-size={12 * viewport.scale}
                        font-weight="bold"
                        fill="#0f172a"
                        pointer-events="none"
                      >
                        {length(marker.ports)}
                      </text>
                    </g>
                    <g :for={{id, s} <- @map_ships} data-map-ship={id}>
                      <% [px, py] =
                        WorldMap.project(
                          ship_coordinates(s, @view.public["clock_ms"], @definitions.catalogue)
                        ) %>
                      <circle
                        cx={px}
                        cy={py}
                        r={4 * viewport.scale}
                        vector-effect="non-scaling-stroke"
                        fill="#fbbf24"
                        stroke="#0f172a"
                        role="button"
                        tabindex="0"
                        class="cursor-pointer"
                        aria-label={"Inspect #{s["name"]}"}
                        phx-click="inspect-ship"
                        phx-value-id={id}
                        phx-keydown="inspect-ship"
                        phx-key="Enter"
                      >
                        <title>
                          {s["name"]} · {@view.public["companies"][s["company_id"]]["name"]} · {@definitions.classes[
                            s["class"]
                          ]["name"]}
                        </title>
                      </circle>
                    </g>
                  </svg>
                  <p class="px-4 pb-3 text-xs text-slate-400">
                    Equal Earth map · teal: ports and regions · gold: ships at sea · ships at port appear in Port traffic
                  </p>
                  <div :if={@map_region} id="region-ports" class="border-t border-slate-700 p-4">
                    <p class="mb-3 text-sm text-slate-300">
                      Choose a port in {@map_region} to inspect its market.
                    </p>
                    <div class="flex flex-wrap gap-3">
                      <button
                        :for={name <- Enum.sort(@definitions.catalogue["clusters"][@map_region])}
                        title={@definitions.catalogue["ports"][name]["harbor"]}
                        phx-click="port"
                        phx-value-id={name}
                        aria-pressed={if name == @selected_port, do: "true", else: "false"}
                        class={[
                          "rounded border px-4 py-3 text-left",
                          if(name == @selected_port,
                            do: "border-teal-400 bg-slate-800",
                            else: "border-slate-600 hover:border-teal-600"
                          )
                        ]}
                      >
                        <strong>{name}</strong><span class="block text-sm text-slate-400">{@definitions.catalogue[
                          "ports"
                        ][name]["harbor"]}</span>
                      </button>
                    </div>
                  </div>
                </section>
                <div class="panel-content" tabindex="0" aria-label="Fleet and ship details">
                  <section
                    :if={
                      @inspected_ship && @view.public["ships"][@inspected_ship] &&
                        !(@view.private && @view.private["ships"][@inspected_ship])
                    }
                    id="public-ship-inspector"
                    class="my-6 rounded-xl border border-slate-700 p-5"
                  >
                    <% inspected = @view.public["ships"][@inspected_ship] %>
                    <h2 class="text-xl">{inspected["name"]}</h2>
                    <p>Company: {@view.public["companies"][inspected["company_id"]]["name"]}</p>
                    <p>Class: {@definitions.classes[inspected["class"]]["name"]}</p>
                    <p>
                      Status: {inspected["status"]} · {inspected["port"]}<span :if={
                        inspected["destination"]
                      }> → {inspected[
                        "destination"
                      ]}</span>
                    </p>
                  </section>
                  <section :if={@view.private && @view.private["company"]} class="my-6">
                    <h2 class="mb-3 text-xl">Your fleet</h2>
                    <form id="fleet-filter" phx-change="fleet-status" class="mb-3 text-sm">
                      <label for="fleet-status">Ship status</label>
                      <select
                        id="fleet-status"
                        name="status"
                        class="ml-2 rounded bg-slate-800 px-2 py-1"
                      >
                        <option
                          :for={
                            {value, label} <- [
                              {"all", "All ships"},
                              {"docked", "Docked"},
                              {"loading", "Loading"},
                              {"unloading", "Unloading"},
                              {"sailing", "Sailing"}
                            ]
                          }
                          value={value}
                          selected={@fleet_status == value}
                        >
                          {label}
                        </option>
                      </select>
                    </form>
                    <p
                      :if={
                        !Enum.any?(@view.private["ships"], fn {_, s} ->
                          @fleet_status == "all" || s["status"] == @fleet_status
                        end)
                      }
                      class="mb-3 text-sm text-slate-400"
                    >
                      No ships with this status.
                    </p>
                    <div class="fleet-list">
                      <button
                        :for={{id, s} <- Enum.sort(@view.private["ships"])}
                        :if={@fleet_status == "all" || s["status"] == @fleet_status}
                        phx-click="ship"
                        phx-value-id={id}
                        aria-pressed={if id == @selected_ship, do: "true", else: "false"}
                        class={[
                          "min-w-0 rounded-xl border p-3 text-left break-words",
                          if(id == @selected_ship,
                            do: "border-teal-400 bg-slate-800",
                            else: "border-slate-700"
                          )
                        ]}
                      >
                        <strong>{s["name"]}</strong><p>
                          {@definitions.classes[s["class"]]["name"]} · {s["status"]}
                        </p><p>
                          {s["port"]}<span :if={s["destination"]}> → {s["destination"]}</span>
                        </p>
                        <p :if={s["arrive_ms"]} class="text-teal-300">
                          {minutes(max(0, s["arrive_ms"] - @view.public["clock_ms"]))} min remaining
                        </p>
                      </button>
                    </div>
                    <div :if={@ship} class="mt-4 rounded-xl bg-slate-900 p-5">
                      <h3 class="text-lg">{@ship["name"]} — private manifest</h3>
                      <% occupied =
                        Enum.reduce(@ship["cargo"], %{weight: 0, volume: 0}, fn batch, used ->
                          good = @definitions.catalogue["goods"][batch["good"]]

                          %{
                            weight: used.weight + batch["quantity"] * good["weight_kg"],
                            volume: used.volume + batch["quantity"] * good["volume_l"]
                          }
                        end) %>
                      <p id="ship-capacity" class="text-sm text-slate-400 tabular-nums">
                        Capacity used: {occupied.weight} / {@definitions.classes[@ship["class"]][
                          "weight"
                        ]} kg · {cubic_meters(occupied.volume)} / {cubic_meters(
                          @definitions.classes[@ship["class"]]["volume"]
                        )}
                      </p>
                      <p :if={@ship["cargo"] == []} class="mt-2 text-slate-400">Empty hold</p>
                      <div :if={@ship["cargo"] != []} class="mt-3 overflow-x-auto">
                        <table class="w-full text-sm" aria-label="Ship cargo manifest">
                          <thead class="border-b border-slate-700 text-slate-400">
                            <tr>
                              <th
                                :for={
                                  {column, label} <- [
                                    {"good", "Cargo"},
                                    {"quantity", "Lots"},
                                    {"weight", "Weight"},
                                    {"volume", "Volume"},
                                    {"average_cost", "Average cost / lot"},
                                    {"expires_ms", "First expiry"}
                                  ]
                                }
                                scope="col"
                                aria-sort={
                                  if elem(@manifest_sort, 0) == column,
                                    do:
                                      if(elem(@manifest_sort, 1) == :asc,
                                        do: "ascending",
                                        else: "descending"
                                      ),
                                    else: "none"
                                }
                                class={
                                  if column == "good",
                                    do: "py-2 pr-4 text-left",
                                    else: "px-4 py-2 text-right"
                                }
                              >
                                <button
                                  type="button"
                                  phx-click="sort-manifest"
                                  phx-value-column={column}
                                  class="whitespace-nowrap rounded hover:text-teal-300 focus-visible:outline-2 focus-visible:outline-teal-300"
                                >
                                  {label}<span aria-hidden="true" class="ml-1">{if elem(
                                                                                     @manifest_sort,
                                                                                     0
                                                                                   ) ==
                                                                                     column,
                                                                                   do:
                                                                                     if(
                                                                                       elem(
                                                                                         @manifest_sort,
                                                                                         1
                                                                                       ) ==
                                                                                         :asc,
                                                                                       do: "↑",
                                                                                       else: "↓"
                                                                                     ),
                                                                                   else: "↕"}</span>
                                </button>
                              </th>
                            </tr>
                          </thead>
                          <tbody>
                            <tr
                              :for={
                                b <-
                                  sorted_manifest(
                                    @ship["cargo"],
                                    @definitions.catalogue["goods"],
                                    @manifest_sort
                                  )
                              }
                              id={"manifest-#{String.replace(b["good"], " ", "-")}"}
                              class="border-b border-slate-800 last:border-0"
                            >
                              <th scope="row" class="py-3 pr-4 text-left font-medium">
                                <button
                                  type="button"
                                  phx-click="market-good"
                                  phx-value-good={b["good"]}
                                  aria-label={"View markets for #{cargo_name(b["good"])}"}
                                  class="rounded text-left text-teal-300 underline decoration-teal-700 underline-offset-2 hover:text-teal-100 focus-visible:outline-2 focus-visible:outline-teal-300"
                                >{cargo_name(b["good"])}</button>
                              </th>
                              <td class="px-4 py-3 text-right tabular-nums">{b["quantity"]}</td>
                              <td class="whitespace-nowrap px-4 py-3 text-right tabular-nums">
                                {b["quantity"] *
                                  @definitions.catalogue["goods"][b["good"]]["weight_kg"]} kg
                              </td>
                              <td class="whitespace-nowrap px-4 py-3 text-right tabular-nums">
                                {cargo_volume(
                                  @definitions.catalogue["goods"][b["good"]],
                                  b["quantity"]
                                )}
                              </td>
                              <td class="whitespace-nowrap px-4 py-3 text-right tabular-nums">
                                {money(b["average_cost"])}
                              </td>
                              <td class="whitespace-nowrap py-3 pl-4 text-right tabular-nums">
                                <%= if b["expires_ms"] do %>
                                  {minutes(max(0, b["expires_ms"] - @view.public["clock_ms"]))} min
                                <% else %>
                                  <span aria-label="Does not expire">—</span>
                                <% end %>
                              </td>
                            </tr>
                          </tbody>
                        </table>
                      </div>
                      <.form
                        :if={@ship["status"] == "docked"}
                        for={%{}}
                        id="voyage-preview"
                        phx-submit="preview"
                        phx-change="preview"
                        class="mt-4 flex gap-3"
                      >
                        <select
                          name="destination"
                          aria-label="Destination"
                          class="rounded bg-slate-800 px-3 py-2"
                        ><option value="" selected={is_nil(@destination) or @destination == ""}>
                          Choose a destination before buying
                        </option><option
                          :for={
                            name <-
                              Enum.sort(Map.keys(@definitions.catalogue["ports"])) -- [@ship["port"]]
                          }
                          value={name}
                          selected={name == @destination}
                        >
                          {name}
                        </option></select>
                      </.form>
                      <div :if={@preview} class="mt-3 flex flex-wrap items-center gap-3">
                        <span>{minutes(@preview["duration_ms"])} min · fuel {money(@preview["fuel"])} · estimated crew {money(
                          @preview["crew_estimate"]
                        )} · canals {money(@preview["canal_fees"])}</span><button
                          phx-click="sail"
                          phx-value-request_id={@request_id}
                          class="rounded bg-teal-600 px-4 py-2"
                        >Reserve fuel and sail</button>
                        <.voyage_freshness estimates={@preview["freshness"]} />
                      </div>
                      <.voyage_freshness estimates={@view.private["voyage_freshness"][@ship["id"]]} />
                    </div>
                  </section>
                </div>
              </section>
              <section id="cargo-panel" class="workspace-panel" aria-label="Cargo">
                <h2 class="panel-title">Cargo</h2>
                <div class="panel-content" tabindex="0" aria-label="Cargo markets">
                  <section id="cargo-markets" class="my-6 rounded-xl border border-slate-700 p-5">
                    <div class="flex flex-wrap items-center justify-between gap-3">
                      <h2 class="text-2xl">Markets by cargo</h2>
                      <div
                        id="cargo-market-selector"
                        class="cargo-picker"
                        phx-click-away="close-cargo-menu"
                        phx-keydown="close-cargo-menu"
                        phx-key="Escape"
                      >
                        <button
                          id="market-good"
                          type="button"
                          phx-click="toggle-cargo-menu"
                          aria-expanded={to_string(@cargo_menu_open)}
                          aria-controls="cargo-options"
                          class="cargo-choice rounded bg-slate-800 px-3 py-2"
                        >
                          <span>{if @market_good,
                            do: cargo_name(@market_good),
                            else: "No cargo markets available"}</span>
                          <span class="cargo-spread">{if @market_good,
                            do: (List.keyfind(@cargo_options, @market_good, 0) |> elem(1)).label} ▾</span>
                        </button>
                        <div
                          :if={@cargo_menu_open}
                          id="cargo-options"
                          class="cargo-options"
                          role="group"
                          aria-label="Choose cargo"
                        >
                          <div class="cargo-menu-row cargo-menu-heading px-3 py-2" aria-hidden="true">
                            <span>Cargo</span><span class="cargo-spread">Bid / ask</span><span class="cargo-roi">ROI</span>
                          </div>
                          <button
                            :for={{good, range} <- @cargo_options}
                            type="button"
                            phx-click="market-good"
                            phx-value-good={good}
                            aria-pressed={to_string(good == @market_good)}
                            class="cargo-choice cargo-menu-row px-3 py-2"
                          >
                            <span>{cargo_name(good)}</span>
                            <span class="cargo-spread">{range.label}</span>
                            <span class="cargo-roi" aria-label={"ROI " <> cargo_roi(range.roi)}>{cargo_roi(
                              range.roi
                            )}</span>
                          </button>
                          <p :if={@cargo_options == []} class="p-3">No cargo markets available</p>
                        </div>
                      </div>
                    </div>
                    <form
                      :if={@cargo_roi_varies}
                      id="cargo-sort"
                      phx-change="cargo-sort-roi"
                      class="mt-2 text-sm"
                    >
                      <label class="flex items-center gap-2">
                        <input type="hidden" name="roi" value="false" />
                        <input type="checkbox" name="roi" value="true" checked={@cargo_sort_roi} />
                        Sort by ROI
                      </label>
                      <p class="mt-1 text-xs text-slate-400">
                        Highest first: (best bid − best ask) ÷ best ask, before handling and voyage costs.
                      </p>
                    </form>
                    <p class="my-3 text-sm text-slate-400">
                      Supply and demand in lots · prices per lot, before handling · updated live. Cargo choices show the highest available bid and lowest available ask; — means no market on that side. Select a port to inspect its market.
                    </p>
                    <p class="mb-2 text-xs text-slate-400">
                      {if @ship && @ship["status"] == "docked",
                        do: "Sea-route distances from #{@ship["port"]} in nautical miles.",
                        else: "Select a docked ship to compare sea-route distances."}
                    </p>
                    <div class="cargo-comparison grid gap-2 md:grid-cols-2">
                      <div
                        :for={
                          {side, heading, quantity_key, price_key} <- [
                            {"supply", "Supply", "stock", "ask"},
                            {"demand", "Demand", "demand", "bid"}
                          ]
                        }
                        class="min-w-0 overflow-x-auto"
                      >
                        <% sort = @market_sort[side] %>
                        <% rows = cargo_markets(@definitions, @view, @market_good, side, sort, @ship) %>
                        <h3 class="mb-2 text-lg font-medium">{heading}</h3>
                        <table
                          id={"cargo-#{side}"}
                          class="w-full text-sm"
                          aria-label={heading <> " for selected cargo"}
                        >
                          <thead class="border-b border-slate-700 text-slate-400">
                            <tr>
                              <th
                                :for={
                                  {column, label} <-
                                    [
                                      {"port", "Port"},
                                      {quantity_key, if(side == "demand", do: "Lots", else: heading)},
                                      {price_key,
                                       if(side == "supply", do: "Buy price", else: "Sell price")}
                                    ] ++
                                      if(side == "demand",
                                        do: [{"distance", "nm"}],
                                        else: []
                                      )
                                }
                                scope="col"
                                class={
                                  if column == "port",
                                    do: "py-2 text-left",
                                    else: "px-3 py-2 text-right"
                                }
                                aria-sort={
                                  if elem(sort, 0) == column,
                                    do:
                                      if(elem(sort, 1) == :asc, do: "ascending", else: "descending"),
                                    else: "none"
                                }
                              >
                                <button
                                  type="button"
                                  phx-click="sort-markets"
                                  phx-value-side={side}
                                  phx-value-column={column}
                                  class="whitespace-nowrap rounded hover:text-teal-300 focus-visible:outline-2 focus-visible:outline-teal-300"
                                >
                                  {label}<span aria-hidden="true" class="ml-1">{if elem(sort, 0) ==
                                                                                     column,
                                                                                   do:
                                                                                     if(
                                                                                       elem(sort, 1) ==
                                                                                         :asc,
                                                                                       do: "↑",
                                                                                       else: "↓"
                                                                                     ),
                                                                                   else: "↕"}</span>
                                </button>
                              </th>
                            </tr>
                          </thead>
                          <tbody>
                            <tr
                              :for={quote <- rows}
                              data-port={quote["port"]}
                              class="border-b border-slate-800 last:border-0"
                            >
                              <th scope="row" class="py-2 text-left font-medium">
                                <button
                                  type="button"
                                  phx-click="port"
                                  phx-value-id={quote["port"]}
                                  class="text-teal-300 underline decoration-teal-800 underline-offset-4"
                                >{quote["port"]}</button>
                              </th>
                              <%= if quote["manual"] do %>
                                <td class="px-3 py-2 text-right tabular-nums">
                                  {quote[quantity_key]}
                                </td>
                                <td class="px-3 py-2 text-right tabular-nums">
                                  {if quote[quantity_key] > 0, do: money(quote[price_key]), else: "—"}
                                </td>
                              <% else %>
                                <td colspan="2" class="px-3 py-2 text-right text-slate-400">
                                  Trading not available yet
                                </td>
                              <% end %>
                              <td :if={side == "demand"} class="text-right tabular-nums">
                                {if is_nil(quote["distance"]), do: "—", else: round(quote["distance"])}
                              </td>
                            </tr>
                            <tr :if={rows == []}>
                              <td
                                colspan={if(side == "demand", do: 4, else: 3)}
                                class="py-3 text-slate-400"
                              >
                                No ports for this cargo.
                              </td>
                            </tr>
                          </tbody>
                        </table>
                      </div>
                    </div>
                  </section>
                </div>
              </section>
            </div>
          </div>
        </div>
      </main>
    </Layouts.app>
    """
  end
end
