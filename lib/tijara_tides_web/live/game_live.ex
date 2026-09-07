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
        traffic_grouping: "status",
        selected_ship: nil,
        inspected_ship: nil,
        trade_quantities: %{},
        manifest_sort: {"good", :asc},
        market_good: "Lumber",
        market_sort: %{"supply" => {"ask", :asc}, "demand" => {"bid", :desc}},
        company_draft: %{"name" => "", "port" => "Singapore", "package" => "general"},
        destination: "Shanghai",
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

  def handle_event("traffic-grouping", %{"grouping" => grouping}, socket)
      when grouping in ["status", "company"] do
    {:noreply, assign(socket, :traffic_grouping, grouping)}
  end

  def handle_event("market-good", %{"good" => good}, socket) do
    if socket.assigns.definitions.catalogue["goods"][good],
      do: {:noreply, assign(socket, :market_good, good)},
      else: {:noreply, socket}
  end

  def handle_event("sort-markets", %{"column" => column, "side" => side}, socket)
      when side in ["supply", "demand"] and column in ["port", "stock", "demand", "ask", "bid"] do
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
      quantities = Map.put(socket.assigns.trade_quantities, {side, good}, integer(quantity))
      {:noreply, assign(socket, :trade_quantities, quantities)}
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
      |> Map.update("quantity", 0, &integer/1)
      |> Map.update("limit", 0, &integer/1)

    run(socket, params)
  end

  def handle_event("preview", %{"destination" => dest}, socket) do
    preview = GameServer.preview(socket.assigns.token, socket.assigns.selected_ship, dest)
    {:noreply, assign(socket, destination: dest, preview: preview)}
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

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp run(socket, command) do
    {request, command} = Map.pop(command, "request_id", socket.assigns.request_id)

    case GameServer.command(socket.assigns.token, request, command) do
      {:ok, result} ->
        socket = if result["code"], do: assign(socket, :invite_code, result["code"]), else: socket

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
          view.private["ships"] |> Map.values() |> Enum.sort_by(& &1["id"]) |> List.first()
      end

    preview =
      if socket.assigns.preview && ship && ship["status"] == "docked",
        do: GameServer.preview(socket.assigns.token, ship["id"], socket.assigns.destination)

    assign(socket, view: view, selected_ship: ship && ship["id"], ship: ship, preview: preview)
  end

  defp owns_ship_at_port?(nil, _port), do: false

  defp owns_ship_at_port?(private, port) do
    Enum.any?(private["ships"], fn {_, ship} ->
      ship["port"] == port and ship["status"] != "sailing"
    end)
  end

  # Keep persisted good IDs stable when their player-facing names change.
  defp cargo_name(good), do: GameServer.cargo_name(good)

  defp cargo_markets(definitions, view, good, side, {column, direction}) do
    rows =
      for {port, definition} <- definitions.catalogue["ports"],
          String.contains?(
            definition["roles"][good],
            if(side == "supply", do: "exp", else: "imp")
          ),
          quote = view.markets[port <> "|" <> good],
          do: Map.put(quote, "port", port)

    {available, unavailable} = Enum.split_with(rows, & &1["manual"])

    sorted =
      if column in ["ask", "bid"] do
        quantity_key = if side == "supply", do: "stock", else: "demand"

        Enum.sort_by(available, fn quote ->
          price = if direction == :asc, do: quote[column], else: -quote[column]
          {price, -quote[quantity_key], quote["port"]}
        end)
      else
        Enum.sort_by(available, &{&1[column], &1["port"]}, direction)
      end

    sorted ++ Enum.sort_by(unavailable, & &1["port"])
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
  defp money(cents), do: "$" <> :erlang.float_to_binary(cents / 100, decimals: 2)
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
    required = fuel + canal

    "Departure requires #{money(required)}: #{money(fuel)} for fuel and #{money(canal)} in canal fees. " <>
      "You have #{money(available)} available after reservations, leaving a shortfall of #{money(required - available)}."
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
    ~H"""
    <Layouts.app flash={@flash}>
      <main class="mx-auto max-w-7xl p-6 text-slate-100">
        <header class="mb-8 flex flex-wrap items-center justify-between gap-4">
          <div>
            <a href="/" class="text-sm text-teal-300">Tijara Tides</a><h1 class="mt-2 text-3xl font-semibold">
              Build a company. Trade the world.
            </h1>
          </div>
          <span class="rounded-full border border-teal-800 px-4 py-2 text-sm text-teal-200">First playable milestone</span>
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
        <div :if={@view.status == :ready}>
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
                class="rounded bg-slate-800 px-4 py-2"
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
          <section
            :if={@view.private}
            class="mb-6 rounded-xl border border-amber-800 p-4 text-sm text-amber-100"
          >
            Keep this device session: identity linking is not included in this first milestone. Losing the session permanently loses access to this account. Invitations cannot be reused to sign in.
          </section>
          <section
            :if={@view.private && @view.private["company"]}
            class="mb-6 grid gap-4 md:grid-cols-4"
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
          <section class="overflow-hidden rounded-xl border border-slate-700 bg-slate-950">
            <% viewport = WorldMap.viewport(@definitions.catalogue, @map_region) %>
            <div :if={@map_region} class="flex items-center justify-between px-4 py-3">
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
                :for={ring <- Map.get(@definitions.regional_land, @map_region, @definitions.land)}
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
              <g :for={{_, s} <- @view.public["ships"]} :if={s["status"] == "sailing"}>
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
                  x={hd(marker.center) + WorldMap.label_position(marker.name).dx * viewport.scale}
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
              <g :for={{id, s} <- @view.public["ships"]} :if={s["status"] == "sailing"}>
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
              Status: {inspected["status"]} · {inspected["port"]}<span :if={inspected["destination"]}> → {inspected[
                "destination"
              ]}</span>
            </p>
          </section>
          <section :if={@view.private && @view.private["company"]} class="my-6">
            <h2 class="mb-3 text-xl">Your fleet</h2>
            <div class="grid gap-3 md:grid-cols-3">
              <button
                :for={{id, s} <- Enum.sort(@view.private["ships"])}
                phx-click="ship"
                phx-value-id={id}
                aria-pressed={if id == @selected_ship, do: "true", else: "false"}
                class={[
                  "rounded-xl border p-4 text-left",
                  if(id == @selected_ship,
                    do: "border-teal-400 bg-slate-800",
                    else: "border-slate-700"
                  )
                ]}
              >
                <strong>{s["name"]}</strong><p>
                  {@definitions.classes[s["class"]]["name"]} · {s["status"]}
                </p><p>{s["port"]}<span :if={s["destination"]}> → {s["destination"]}</span></p>
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
                Capacity used: {occupied.weight} / {@definitions.classes[@ship["class"]]["weight"]} kg · {cubic_meters(
                  occupied.volume
                )} / {cubic_meters(@definitions.classes[@ship["class"]]["volume"])}
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
                              if(elem(@manifest_sort, 1) == :asc, do: "ascending", else: "descending"),
                            else: "none"
                        }
                        class={
                          if column == "good", do: "py-2 pr-4 text-left", else: "px-4 py-2 text-right"
                        }
                      >
                        <button
                          type="button"
                          phx-click="sort-manifest"
                          phx-value-column={column}
                          class="whitespace-nowrap rounded hover:text-teal-300 focus-visible:outline-2 focus-visible:outline-teal-300"
                        >
                          {label}<span aria-hidden="true" class="ml-1">{if elem(@manifest_sort, 0) ==
                                                                             column,
                                                                           do:
                                                                             if(
                                                                               elem(@manifest_sort, 1) ==
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
                        {cargo_name(b["good"])}
                      </th>
                      <td class="px-4 py-3 text-right tabular-nums">{b["quantity"]}</td>
                      <td class="whitespace-nowrap px-4 py-3 text-right tabular-nums">
                        {b["quantity"] * @definitions.catalogue["goods"][b["good"]]["weight_kg"]} kg
                      </td>
                      <td class="whitespace-nowrap px-4 py-3 text-right tabular-nums">
                        {cargo_volume(@definitions.catalogue["goods"][b["good"]], b["quantity"])}
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
                class="mt-4 flex gap-3"
              >
                <select
                  name="destination"
                  aria-label="Destination"
                  class="rounded bg-slate-800 px-3 py-2"
                ><option
                  :for={
                    name <- Enum.sort(Map.keys(@definitions.catalogue["ports"])) -- [@ship["port"]]
                  }
                  value={name}
                  selected={name == @destination}
                >
                  {name}
                </option></select>
                <button class="rounded border border-teal-600 px-4">Estimate voyage</button>
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
          <section id="cargo-markets" class="my-6 rounded-xl border border-slate-700 p-5">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <h2 class="text-2xl">Markets by cargo</h2>
              <form id="cargo-market-selector" phx-change="market-good">
                <label for="market-good" class="mr-2">Cargo</label>
                <select id="market-good" name="good" class="rounded bg-slate-800 px-3 py-2">
                  <option
                    :for={
                      {good, _} <-
                        Enum.sort_by(@definitions.catalogue["goods"], fn {good, _} ->
                          cargo_name(good)
                        end)
                    }
                    value={good}
                    selected={good == @market_good}
                  >
                    {cargo_name(good)}
                  </option>
                </select>
              </form>
            </div>
            <p class="my-3 text-sm text-slate-400">
              Supply and demand in lots · prices per lot, before handling · updated live. Select a port to inspect its market.
            </p>
            <div class="grid gap-6 md:grid-cols-2">
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
                <% rows = cargo_markets(@definitions, @view, @market_good, side, sort) %>
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
                          {column, label} <- [
                            {"port", "Port"},
                            {quantity_key, heading},
                            {price_key, if(side == "supply", do: "Buy price", else: "Sell price")}
                          ]
                        }
                        scope="col"
                        class={
                          if column == "port", do: "py-2 text-left", else: "px-3 py-2 text-right"
                        }
                        aria-sort={
                          if elem(sort, 0) == column,
                            do: if(elem(sort, 1) == :asc, do: "ascending", else: "descending"),
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
                          {label}<span aria-hidden="true" class="ml-1">{if elem(sort, 0) == column,
                            do: if(elem(sort, 1) == :asc, do: "↑", else: "↓"),
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
                        <td class="px-3 py-2 text-right tabular-nums">{quote[quantity_key]}</td>
                        <td class="px-3 py-2 text-right tabular-nums">
                          {if quote[quantity_key] > 0, do: money(quote[price_key]), else: "—"}
                        </td>
                      <% else %>
                        <td colspan="2" class="px-3 py-2 text-right text-slate-400">
                          Trading not available yet
                        </td>
                      <% end %>
                    </tr>
                    <tr :if={rows == []}>
                      <td colspan="3" class="py-3 text-slate-400">No ports for this cargo.</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </section>
          <section class="my-6 rounded-xl border border-slate-700 p-5">
            <div class="flex flex-wrap justify-between gap-3">
              <h2 class="text-2xl">{@selected_port}</h2><form id="port-selector" phx-change="port">
                <select aria-label="Inspect port" name="id" class="rounded bg-slate-800 px-3 py-2"><option
                  :for={name <- Enum.sort(Map.keys(@definitions.catalogue["ports"]))}
                  value={name}
                  selected={name == @selected_port}
                >
                  {name}
                </option></select>
              </form>
            </div>
            <p class="my-3 text-slate-300">
              {@definitions.catalogue["ports"][@selected_port]["identity"]}
            </p>
            <TijaraTidesWeb.PortTraffic.traffic
              public={@view.public}
              port={@selected_port}
              grouping={@traffic_grouping}
            />
            <p class="mb-3 text-sm text-slate-400">
              Whole lots · finite local supply and demand · trades require your selected ship to be docked here. Handling takes time.
            </p>
            <% market_rows = visible_market_rows(@definitions, @view, @ship, @selected_port) %>
            <% show_ship_columns = owns_ship_at_port?(@view.private, @selected_port) %>
            <% selected_ship_here =
              @ship && @ship["port"] == @selected_port && @ship["status"] != "sailing" %>
            <p :if={market_rows == []} class="py-4 text-slate-400">
              No cargo is available to trade here right now.
            </p>
            <div :if={market_rows != []} class="overflow-x-auto">
              <table class="w-full text-left text-sm">
                <thead class="text-slate-400">
                  <tr>
                    <th class="py-2">Cargo / lot size</th><th>Buy / supply</th><th>Sell / demand</th><th :if={
                      show_ship_columns
                    }>
                      Aboard (lots)
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
                    <td class="py-3">
                      {cargo_name(good)}
                      <p class="text-xs text-slate-400">
                        {item["weight_kg"]} kg · {cargo_volume(item, 1)}
                        <span :if={q["manual"]}> · handling {money(q["handling_fee"])} / lot</span>
                      </p>
                    </td>
                    <td>{money(q["ask"])} / {q["stock"]}</td><td>
                      {money(q["bid"])} / {q["demand"]}
                    </td>
                    <td
                      :if={show_ship_columns}
                      id={"aboard-#{String.replace(good, " ", "-")}"}
                      class="font-semibold text-teal-200"
                    >
                      {if selected_ship_here, do: cargo_aboard(@ship, good), else: "—"}
                    </td>
                    <td :if={show_ship_columns}>
                      <span :if={!q["manual"]} class="text-slate-500">Available in a later market milestone</span>
                      <.form
                        :for={side <- ["buy", "sell"]}
                        :if={
                          q["manual"] && @ship && @ship["port"] == @selected_port &&
                            @ship["status"] == "docked"
                        }
                        for={%{}}
                        id={"trade-#{side}-#{String.replace(good, " ", "-")}"}
                        phx-submit="trade"
                        phx-change="trade-preview"
                        class="flex flex-wrap gap-2"
                      >
                        <% available = available_to_trade(side, q, @ship, good) %>
                        <% quantity =
                          if available > 0, do: Map.get(@trade_quantities, {side, good}, 1), else: 0 %>
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
                          type="number"
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
                                  do: "No stock available at this port",
                                  else: "No cargo aboard or no demand at this port"
                                )
                          }
                          class="rounded bg-teal-700 px-3 py-1 disabled:cursor-not-allowed disabled:bg-slate-700 disabled:text-slate-400 disabled:opacity-60"
                        >{String.capitalize(side)}</button>
                        <%= if side == "buy" and available > 0 and quantity > 0 do %>
                          <% total = GameServer.purchase_total(q, @ship, item, quantity) %>
                          <% unaffordable =
                            total >
                              @view.private["company"]["cash"] - @view.private["company"]["reserved"] or
                              @view.private["company"]["unpaid"] > 0 %>
                          <span
                            class={[
                              "purchase-total self-center whitespace-nowrap text-sm tabular-nums",
                              if(unaffordable, do: "text-red-400", else: "text-slate-300")
                            ]}
                            title={
                              if unaffordable,
                                do:
                                  "Insufficient available funds. Includes handling and any tanker cleaning fee.",
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
          <section :if={@view.private} class="my-6 rounded-xl bg-slate-900 p-5">
            <h2 class="text-xl">Invitations & notices</h2><p class="my-2">
              Available entitlements: {@view.private["account"]["invite_quota"]}
            </p>
            <button
              phx-click="invite"
              phx-value-request_id={@request_id}
              class="rounded border border-teal-700 px-4 py-2"
            >Generate shareable invitation</button>
            <p :if={@invite_code} class="mt-3 break-all font-mono text-teal-200">{@invite_code}</p>
            <p :for={notice <- @view.private["notices"]} class="mt-3">{notice["text"]}</p>
          </section>
        </div>
      </main>
    </Layouts.app>
    """
  end
end
