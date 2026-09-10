defmodule TijaraTidesWeb.GameLive do
  use TijaraTidesWeb, :live_view
  alias TijaraTides.Infrastructure.{GameServer, GameQueries, WorldServer}
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
        browser_id: session["player_id"],
        page_title: "Your shipping company",
        definitions: GameServer.definitions(),
        selected_port: "Singapore",
        report_open: false,
        report_data: nil,
        report_error: nil,
        report_selection: %{"period" => "quarter", "metric" => "profit", "index" => nil},
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
        instruction_drafts: %{},
        manifest_sort: {"good", :asc},
        market_good: "lumber",
        cargo_menu_open: false,
        cargo_sort_roi: false,
        cargo_filter_ship: false,
        market_sort: %{"supply" => {"ask", :asc}, "demand" => {"bid", :desc}},
        company_draft: %{"name" => "", "port" => "Singapore"},
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
  def handle_event("report-toggle", _, socket) do
    if socket.assigns.report_open,
      do: {:noreply, assign(socket, report_open: false, report_data: nil, report_error: nil)},
      else: {:noreply, socket |> assign(:report_open, true) |> load_reports()}
  end

  def handle_event("report-close", _, socket),
    do: {:noreply, assign(socket, report_open: false, report_data: nil, report_error: nil)}

  def handle_event("report-refresh", _, socket), do: {:noreply, load_reports(socket)}

  def handle_event("report-page", %{"page" => page}, socket) do
    page = report_number(page) || 0

    {:noreply,
     socket
     |> assign(:report_selection, Map.put(socket.assigns.report_selection, "page", page))
     |> load_reports()}
  end

  def handle_event("report-own-page", %{"page" => page}, socket) do
    {:noreply,
     socket
     |> assign(
       :report_selection,
       Map.put(socket.assigns.report_selection, "own_page", report_number(page) || 0)
     )
     |> load_reports()}
  end

  def handle_event("report-selection", params, socket) do
    previous = socket.assigns.report_selection
    period = if params["period"] == "year", do: "year", else: "quarter"
    number = report_number(params["period_number"])

    index =
      cond do
        period != previous["period"] -> nil
        is_integer(number) -> number - 1
        true -> previous["index"]
      end

    # The client controls this payload; carry only the bounded fields the query reads.
    {:noreply,
     socket
     |> assign(:report_selection, %{
       "period" => period,
       "metric" => if(params["metric"] == "roi", do: "roi", else: "profit"),
       "index" => index,
       "page" => 0,
       "own_page" => 0
     })
     |> load_reports()}
  end

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

  def handle_event("cargo-filter-ship", params, socket) do
    {:noreply, assign(socket, :cargo_filter_ship, params["compatible"] == "true")}
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

  def handle_event("close-map-ship", _params, socket) do
    {:noreply, assign(socket, :inspected_ship, nil)}
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
      port = if own["status"] == "sailing", do: socket.assigns.selected_port, else: own["port"]

      {:noreply,
       socket
       |> assign(selected_ship: id, selected_port: port, inspected_ship: id, preview: nil)
       |> refresh()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("company-preview", params, socket),
    do: {:noreply, assign(socket, company_draft: Map.take(params, ["name"]))}

  def handle_event("purchase-ship", params, socket) do
    run(socket, %{
      "action" => "purchase_ship",
      "class" => params["class"],
      "port" => socket.assigns.selected_port,
      "price_limit" => integer(params["price_limit"]),
      "request_id" => params["request_id"]
    })
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

  def handle_event("email-request", params, socket) do
    if Application.get_env(:tijara_tides, :email_enabled, false) do
      case GameServer.email_request(
             socket.assigns.token,
             params["purpose"],
             params["email"],
             socket.assigns.request_id,
             socket.assigns.browser_id
           ) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(request_id: GameServer.request_id())
           |> put_flash(
             :info,
             "Email queued. Check the recipient's inbox for the verification link."
           )
           |> refresh()}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, error_message(reason))}
      end
    else
      {:noreply,
       put_flash(socket, :error, "Email delivery has not been configured on this server.")}
    end
  end

  def handle_event("invite", params, socket), do: run(socket, Map.put(params, "action", "invite"))

  def handle_event("edit-instruction", params, socket) do
    previous = Map.get(socket.assigns.instruction_drafts, socket.assigns.selected_ship, %{})

    visit_port =
      instruction_port(
        socket.assigns.ship,
        socket.assigns.destination,
        socket.assigns.definitions
      )

    previous =
      if previous["visit_port"] && previous["visit_port"] != visit_port,
        do: Map.drop(previous, ["quantity", "limit"]),
        else: previous

    target = List.last(params["_target"] || [])

    fields =
      if target in ~w(side good quantity limit budget onward),
        do: [target],
        else: ~w(side good quantity limit budget onward)

    draft = Map.merge(previous, Map.take(params, fields))
    draft = if target in ["side", "good"], do: Map.drop(draft, ["quantity", "limit"]), else: draft

    draft =
      Map.put(
        draft,
        "visit_port",
        instruction_port(
          socket.assigns.ship,
          socket.assigns.destination,
          socket.assigns.definitions
        )
      )

    {:noreply,
     assign(
       socket,
       :instruction_drafts,
       Map.put(socket.assigns.instruction_drafts, socket.assigns.selected_ship, draft)
     )}
  end

  def handle_event("add-instruction", params, socket) do
    run(
      socket,
      params
      |> Map.put("action", "instruction")
      |> Map.put("ship", socket.assigns.selected_ship)
      |> Map.put(
        "port",
        instruction_port(
          socket.assigns.ship,
          socket.assigns.destination,
          socket.assigns.definitions
        )
      )
      |> Map.update("quantity", 0, &integer/1)
      |> Map.update("limit", 0, &instruction_cents/1)
      |> Map.update("budget", 0, &(integer(&1) * 100))
    )
  end

  def handle_event("sell-ship", params, socket) do
    run(socket, %{
      "action" => "sell_ship",
      "ship" => params["ship"],
      "minimum" => integer(params["minimum"]),
      "request_id" => params["request_id"]
    })
  end

  def handle_event("guarantee", params, socket) do
    run(socket, %{
      "action" => "guarantee",
      "account" => params["account"],
      "amount" => integer(params["amount"]) * 100,
      "request_id" => params["request_id"]
    })
  end

  def handle_event("borrow", params, socket) do
    run(socket, %{
      "action" => "borrow",
      "amount" => integer(params["amount"]) * 100,
      "request_id" => params["request_id"]
    })
  end

  def handle_event("recast", params, socket) do
    run(socket, %{
      "action" => "recast",
      "loan" => params["loan"],
      "amount" => integer(params["amount"]) * 100,
      "request_id" => params["request_id"]
    })
  end

  def handle_event("repay", params, socket),
    do:
      run(socket, %{
        "action" => "repay",
        "loan" => params["loan"],
        "request_id" => params["request_id"]
      })

  def handle_event("bankruptcy", params, socket),
    do: run(socket, %{"action" => "bankruptcy", "request_id" => params["request_id"]})

  def handle_event("instruction-onward", params, socket) do
    run(
      socket,
      params
      |> Map.put("action", "instruction_onward")
      |> Map.put("auto_depart", params["auto_depart"] == "true")
      |> Map.put("ship", socket.assigns.selected_ship)
    )
  end

  def handle_event("cancel-instruction", %{"id" => id}, socket) do
    run(socket, %{"action" => "cancel_instruction", "instruction" => id})
  end

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

        {:noreply,
         socket
         |> assign(preview: nil, request_id: GameServer.request_id())
         |> put_flash(:info, "Done.")
         |> refresh()}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, error_message(reason)) |> refresh()}
    end
  end

  defp report_number(value) when is_integer(value), do: value

  defp report_number(value) when is_binary(value) and byte_size(value) <= 12 do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp report_number(_), do: nil

  defp load_reports(socket) do
    case GameServer.reports(socket.assigns.token, socket.assigns.report_selection) do
      {:ok, data} ->
        assign(socket,
          report_data: data,
          report_error: nil,
          report_selection: %{
            "period" => data.period,
            "metric" => data.metric,
            "index" => data.selected,
            "page" => data.page,
            "own_page" => data.own_page
          }
        )

      {:error, error} ->
        assign(socket, report_data: nil, report_error: error)
    end
  end

  defp refresh(socket) do
    view = GameServer.snapshot(socket.assigns.token)

    if connected?(socket) do
      if view.private,
        do: WorldServer.attach(socket.assigns.browser_id),
        else: WorldServer.detach()
    end

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

    planned =
      if ship && view.private,
        do: get_in(view.private, ["visit_plans", ship["id"] <> "|" <> ship["port"], "onward"])

    socket =
      if planned && socket.assigns.destination in [nil, "", ship["port"]],
        do: assign(socket, :destination, planned),
        else: socket

    preview =
      if socket.assigns.destination not in [nil, ""] && ship && ship["status"] == "docked",
        do: GameServer.preview(socket.assigns.token, ship["id"], socket.assigns.destination)

    socket =
      if ship && is_nil(socket.assigns.selected_ship),
        do: assign(socket, :selected_port, ship["port"]),
        else: socket

    limits = GameQueries.trade_limits(view, ship, socket.assigns.destination)
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

  defp route_distance(definitions, ship, destination),
    do: GameQueries.route_distance(definitions, ship, destination)

  defp cargo_markets(definitions, view, good, side, sort, ship),
    do: GameQueries.cargo_markets(definitions, view, good, side, sort, ship)

  defp cargo_roi(nil), do: "—"
  defp cargo_roi(roi), do: :erlang.float_to_binary(roi * 100, decimals: 2) <> "%"

  defp visible_market_rows(definitions, view, ship, port),
    do: GameQueries.visible_market_rows(definitions, view, ship, port)

  defp cargo_aboard(ship, good), do: GameQueries.cargo_aboard(ship, good)
  defp sorted_manifest(cargo, goods, sort), do: GameQueries.sorted_manifest(cargo, goods, sort)

  defp manifest(cargo), do: GameQueries.manifest(cargo)

  defp instruction_port(nil, _destination, _definitions), do: nil

  defp instruction_port(ship, destination, definitions) do
    port = ship["destination"] || destination

    if is_binary(port) and port != ship["port"] and
         Map.has_key?(definitions.catalogue["ports"], port),
       do: port
  end

  defp instruction_cents(value) do
    case Decimal.parse(to_string(value)) do
      {amount, ""} -> amount |> Decimal.mult(100) |> Decimal.round(0) |> Decimal.to_integer()
      _ -> 0
    end
  end

  defp instruction_value(drafts, ship, key, default),
    do: Map.get(Map.get(drafts, ship["id"], %{}), key, default)

  defp ship_instructions(private, ship_id) do
    private["ship_instructions"]
    |> Map.values()
    |> Enum.filter(&(&1["ship_id"] == ship_id))
    |> Enum.sort_by(
      &{if(&1["status"] in ["planned", "waiting"], do: 0, else: 1), -&1["created_ms"], &1["id"]}
    )
    |> Enum.take(40)
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
  attr :id, :string, required: true

  defp voyage_freshness(assigns) do
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

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> -1
    end
  end

  defp integer(_), do: -1
  defp dollars(whole), do: "$" <> Integer.to_string(whole)
  defp money(cents), do: dollars(round(cents / 100))

  defp finance_money(cents),
    do:
      dollars(div(cents, 100)) <>
        "." <> String.pad_leading(Integer.to_string(rem(cents, 100)), 2, "0")

  defp minutes(ms), do: Float.round(ms / 60000, 1)

  defp invitation_time_remaining(ms) do
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

  defp active_countdown(ms) do
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
        "Dock and empty the ship, then clear pending cargo instructions and onward plans before selling.",
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
      for {good, quote} <-
            GameQueries.cargo_options(
              assigns.definitions,
              assigns.view,
              assigns.cargo_sort_roi,
              if(assigns.cargo_filter_ship, do: assigns.ship)
            ) do
        label =
          "bid #{if quote.bid, do: money(quote.bid), else: "—"} / ask #{if quote.ask, do: money(quote.ask), else: "—"}"

        {good, Map.put(quote, :label, label)}
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
      <main
        id="game-screen"
        phx-hook="PopupAnchor"
        class={[
          "game-screen text-slate-100",
          @view.private && @view.private["company"] && "game-screen-playing"
        ]}
      >
        <header class="game-header flex items-center justify-between gap-3">
          <div>
            <a href="/" class="text-sm text-teal-300">Tijara Tides</a><h1 class="game-tagline text-sm font-semibold">
              Build a company. Trade the world.
            </h1>
          </div>
          <div :if={@view.status == :ready} class="game-header-actions">
            <TijaraTidesWeb.FinancialReports.panel
              data={@report_data}
              open={@report_open}
              error={@report_error}
            />
            <details
              :if={@view.private}
              id="company-menu"
              class="company-menu"
              phx-mounted={JS.ignore_attributes("open")}
            >
              <summary class="company-menu-trigger popup-menu-trigger" phx-click="report-close">
                <span>Account, finance &amp; invitations</span>
              </summary>
              <div class="company-menu-body">
                <div class="company-menu-dismiss">
                  <h3
                    :if={@view.private["account"]["email"]}
                    id="verified-email"
                    class="min-w-0 flex-1 break-words"
                  >
                    Verified Email identity: {@view.private["account"]["email"]}
                  </h3>
                  <button
                    type="button"
                    phx-click={
                      JS.remove_attribute("open", to: "#company-menu")
                      |> JS.focus(to: "#company-menu > summary")
                    }
                    aria-label="Close account, finance and invitations"
                    class="shrink-0 rounded border border-slate-500 px-3 py-1"
                  >Close ✕</button>
                </div>
                <p :if={is_nil(@view.private["account"]["email"])} class="text-sm text-amber-100">
                  <%= if Application.get_env(:tijara_tides, :email_enabled, false) do %>
                    Link an email to sign in on another device. Until an email is verified, keep this device session to retain access. Invitations cannot be reused to sign in.
                  <% else %>
                    Email linking is not available on this server yet. Keep this device session to retain access. Invitations cannot be reused to sign in.
                  <% end %>
                </p>
                <section class="my-6 rounded-xl bg-slate-900 p-5">
                  <section
                    :if={
                      Application.get_env(:tijara_tides, :email_enabled, false) and
                        is_nil(@view.private["account"]["email"])
                    }
                    id="email-identity"
                    class="my-4 space-y-2"
                  >
                    <h3 :if={is_nil(@view.private["account"]["email"])}>Email identity</h3>
                    <div :if={is_nil(@view.private["account"]["email"])} id="email-verification">
                      <.form
                        for={%{}}
                        id="email-link-form"
                        phx-submit="email-request"
                        class="flex flex-wrap gap-2"
                      >
                        <input type="hidden" name="purpose" value="link" />
                        <input
                          type="email"
                          name="email"
                          required
                          maxlength="254"
                          aria-label="Email to link"
                          class="rounded bg-slate-800 p-2"
                        />
                        <div class="flex items-center gap-2">
                          <button class="shrink-0 rounded border p-2">Send verification link</button>
                          <p class="text-sm">Verify your email using the link we send.</p>
                        </div>
                      </.form>
                      <p class="text-sm">
                        Addresses already linked to another account cannot be used.
                      </p>
                      <ul class="text-xs space-y-1">
                        <li
                          :for={delivery <- @view.private["email_deliveries"] || []}
                          :if={delivery["purpose"] == "link"}
                        >
                          {delivery["email"]}: {if delivery["verified"],
                            do: "verified",
                            else: delivery["delivery"]}
                        </li>
                      </ul>
                    </div>
                  </section>
                  <section
                    :if={@view.private["account"]["email"]}
                    id="invitations"
                    class="my-4 space-y-2"
                  >
                    <h2 class="text-xl">Invitations</h2>
                    <p :if={@view.private["account"]["invite_quota"] < 1}>Available invitations: 0</p>
                    <div
                      :if={@view.private["account"]["invite_quota"] > 0}
                      class="flex flex-wrap items-end gap-3"
                    >
                      <div class="min-w-0 flex-[1_1_16rem] space-y-1">
                        <p>Available invitations: {@view.private["account"]["invite_quota"]}</p>
                        <.form
                          :if={Application.get_env(:tijara_tides, :email_enabled, false)}
                          for={%{}}
                          id="email-invite-form"
                          phx-submit="email-request"
                          class="flex flex-wrap gap-2"
                        >
                          <input type="hidden" name="purpose" value="invite" />
                          <input
                            type="email"
                            name="email"
                            required
                            maxlength="254"
                            aria-label="Invitee email"
                            placeholder="Invitee email"
                            class="min-w-0 flex-1 rounded bg-slate-800 p-2"
                          />
                          <button
                            disabled={
                              @view.private["account"]["invite_quota"] < 1 or
                                not is_nil(@view.private["account"]["suspended_ms"])
                            }
                            class="rounded border p-2 disabled:opacity-40"
                          >Send invitation</button>
                        </.form>
                      </div>
                      <span
                        :if={Application.get_env(:tijara_tides, :email_enabled, false)}
                        class="py-2 text-slate-400"
                      >or</span>
                      <button
                        phx-click="invite"
                        phx-value-request_id={@request_id}
                        class="rounded border border-teal-700 px-4 py-2"
                      >Generate shareable<br />invitation code</button>
                    </div>
                    <p :if={@invite_code} class="mt-3 break-all font-mono text-teal-200">
                      {@invite_code}
                    </p>
                    <p
                      :if={
                        @view.private["account"]["invite_quota"] > 0 and
                          Application.get_env(:tijara_tides, :email_enabled, false)
                      }
                      class="text-sm"
                    >
                      Uses one invitation. The recipient verifies the email when redeeming the link. You will not receive their sign-in credential.
                    </p>
                    <ul class="text-xs space-y-1">
                      <li
                        :for={delivery <- @view.private["email_deliveries"] || []}
                        :if={delivery["purpose"] == "invite"}
                      >
                        {delivery["email"]}: {if delivery["verified"],
                          do: "verified",
                          else: delivery["delivery"]}
                        <span :if={delivery["purpose"] == "invite" and not delivery["verified"]}>
                          · expires in {invitation_time_remaining(
                            max(0, delivery["expires_ms"] - @view.public["clock_ms"])
                          )}
                        </span>
                      </li>
                    </ul>
                  </section>
                  <section
                    :if={
                      @view.private["guarantees"]["active"] != nil or
                        @view.private["guarantees"]["pending"] != [] or
                        Enum.any?(
                          @view.private["guarantees"]["pledges"],
                          &(&1["status"] == "pledged")
                        )
                    }
                    id="sponsor-guarantees"
                    class="my-4 space-y-3"
                  >
                    <h3 class="text-lg">Sponsor guarantees</h3>
                    <p :if={not @view.private["guarantees"]["eligible"]}>
                      To sponsor a player, clear overdue bills and hold at least as much unreserved cash as your own outstanding loan principal and interest.
                    </p>

                    <p :if={@view.private["guarantees"]["active"]}>
                      Your borrowing is backed by a {money(
                        @view.private["guarantees"]["active"]["amount"]
                      )} sponsor pledge.
                    </p>

                    <div
                      :for={g <- @view.private["guarantees"]["pledges"]}
                      :if={g["status"] == "pledged"}
                    >
                      {money(g["amount"])} locked as a guarantee. It is returned to the sponsoring company after the guaranteed loans are repaid; on bankruptcy, unpaid loan debt is covered up to this cap and the rest is refunded.
                    </div>
                    <.form
                      :for={candidate <- @view.private["guarantees"]["pending"]}
                      :if={
                        @view.private["company"] && is_nil(@view.private["account"]["suspended_ms"])
                      }
                      for={%{}}
                      id={"guarantee-" <> candidate["id"]}
                      phx-submit="guarantee"
                      data-confirm="Fund this guarantee? Cash is locked immediately, including before the invitee borrows. It can be forfeited on their bankruptcy and is not withdrawable. Your own bankruptcy does not release it."
                      class="space-y-2 rounded border p-3"
                    >
                      <p>
                        Guarantee {candidate["name"]}. The pledge caps their borrowing and your liability.
                      </p>
                      <input type="hidden" name="request_id" value={@request_id} />
                      <input type="hidden" name="account" value={candidate["id"]} />
                      <input
                        type="number"
                        name="amount"
                        aria-label="Sponsor pledge in dollars"
                        min="50000"
                        max={
                          div(
                            min(
                              candidate["limit"],
                              @view.private["company"]["cash"] - @view.private["company"]["reserved"]
                            ),
                            100
                          )
                        }
                        value="50000"
                        class="w-32 rounded bg-slate-800 p-2"
                      />
                      <button
                        disabled={
                          not @view.private["guarantees"]["eligible"] or
                            @view.private["company"]["cash"] - @view.private["company"]["reserved"] <
                              5_000_000
                        }
                        phx-disable-with="Pledging…"
                        class="rounded border p-2"
                      >Pledge &amp; reinstate</button>
                    </.form>
                  </section>
                  <section
                    :if={@view.private["company"]}
                    id="company-finance"
                    class="mt-4 space-y-3 border-t border-slate-600 pt-3"
                  >
                    <h3 class="text-lg">Loans and repayments</h3>

                    <p :if={
                      @view.private["finance"]["rate_bps"] == 1600 &&
                        is_nil(@view.private["guarantees"]["active"])
                    }>
                      New borrowing requires your original sponsor's cash pledge, even after earlier guaranteed loans were repaid.
                    </p>
                    <p>
                      Debt: {money(@view.private["finance"]["debt"])} · Available credit: {money(
                        @view.private["finance"]["available"]
                      )} · Lifetime bankruptcies: {@view.private["account"]["bankruptcies"]}
                    </p>
                    <details id="loan-terms" phx-mounted={JS.ignore_attributes("open")}>
                      <summary class="cursor-pointer">Loan terms</summary>
                      <p class="mt-2 text-sm">
                        New loans have {@view.private["finance"]["installments"]} installments and accrue {@view.private[
                          "finance"
                        ]["rate_bps"] / 100}% interest per {div(
                          @view.private["finance"]["period_ms"],
                          3_600_000
                        )} active-world hours on
                        outstanding principal, continuously while the world runs. Recent bankruptcies
                        raise rates from 8% to 9%, 10%, 12%, 14%, then 16%; existing loans keep their
                        rate. Early repayment has no penalty and avoids future interest. Borrowing is
                        not profit.
                      </p>
                    </details>
                    <p :if={@view.private["finance"]["deadline"]} class="text-amber-300">
                      Arrears: {money(@view.private["finance"]["arrears"])}. Bankruptcy deadline in {minutes(
                        max(0, @view.private["finance"]["deadline"] - @view.public["clock_ms"])
                      )} active-world minutes. World suspension pauses this countdown.
                    </p>
                    <.form
                      for={%{}}
                      id="loan-form"
                      phx-submit="borrow"
                      phx-hook="LoanAmount"
                      data-max={div(@view.private["finance"]["available"], 100)}
                      class="flex flex-wrap items-center gap-2"
                    >
                      <input
                        type="range"
                        aria-label="Loan amount in $10,000 steps"
                        min="0"
                        max={ceil(div(@view.private["finance"]["available"], 100) / 10_000)}
                        step="1"
                        value={ceil(div(@view.private["finance"]["available"], 100) / 10_000)}
                        disabled={@view.private["finance"]["available"] < 100}
                        class="w-full accent-teal-500"
                      />
                      <input type="hidden" name="request_id" value={@request_id} />
                      <input
                        type="number"
                        name="amount"
                        aria-label="Loan amount in dollars"
                        disabled={@view.private["finance"]["available"] < 100}
                        min="1"
                        max={div(@view.private["finance"]["available"], 100)}
                        value={div(@view.private["finance"]["available"], 100)}
                        class="w-32 rounded bg-slate-800 p-2"
                      />
                      <button
                        disabled={@view.private["finance"]["available"] < 100}
                        phx-disable-with="Borrowing…"
                        class="rounded bg-teal-700 p-2 disabled:opacity-40"
                      >Borrow</button>
                    </.form>
                    <details
                      :for={loan <- @view.private["finance"]["loans"]}
                      :if={loan["status"] == "open"}
                      id={"loan-" <> loan["id"]}
                      phx-mounted={JS.ignore_attributes("open")}
                      class="rounded border border-slate-600 p-2"
                    >
                      <summary>
                        {money(loan["principal"])} loan · {loan["rate_bps"] / 100}% per period · {loan[
                          "status"
                        ]} · {money(loan["remaining"])} principal remaining
                      </summary>
                      <p>
                        Accrued interest not yet due: {finance_money(loan["interest_accrued"])} · Currently due: {money(
                          loan["principal_due"] + loan["interest_due"]
                        )}
                      </p>
                      <table :if={loan["status"] == "open"} class="w-full text-right">
                        <caption class="pb-2 text-left">
                          Projected schedule assuming timely payments in active-world time:
                        </caption><thead>
                          <tr>
                            <th title="Remaining active-world time (HH:MM:SS); pauses when the world is suspended">
                              Due in (HH:MM:SS)
                            </th><th>Principal</th><th>Interest</th>
                          </tr>
                        </thead><tbody>
                          <tr :for={row <- loan["schedule"]}>
                            <td>{active_countdown(row["due_ms"] - @view.public["clock_ms"])}</td><td>
                              {money(row["principal"])}
                            </td><td>{finance_money(row["interest"])}</td>
                          </tr>
                        </tbody>
                      </table>
                      <% recast_min = div(loan["interest_accrued"] + 199, 100) %>
                      <% recast_max =
                        div(
                          min(
                            @view.private["company"]["cash"] - @view.private["company"]["reserved"],
                            loan["remaining"] + loan["interest_accrued"]
                          ),
                          100
                        ) %>
                      <% can_recast =
                        loan["periods_left"] > 0 && loan["principal_due"] == 0 &&
                          loan["interest_due"] == 0 && @view.private["company"]["unpaid"] == 0 &&
                          recast_max >= recast_min %>
                      <% can_repay =
                        loan["status"] == "open" &&
                          @view.private["company"]["cash"] - @view.private["company"]["reserved"] >=
                            loan["remaining"] + loan["interest_due"] + loan["interest_accrued"] %>

                      <div class="my-3 flex flex-wrap items-end gap-3">
                        <.form
                          :if={can_repay}
                          for={%{}}
                          phx-submit="repay"
                          class="shrink-0"
                        >
                          <input type="hidden" name="request_id" value={@request_id} /><input
                            type="hidden"
                            name="loan"
                            value={loan["id"]}
                          />
                          <button phx-disable-with="Repaying…" class="rounded border p-2">Repay<br />{finance_money(
                            loan["remaining"] + loan["interest_due"] + loan["interest_accrued"]
                          )}<br />in full</button>
                        </.form>
                        <.form
                          :if={can_recast}
                          for={%{}}
                          id={"recast-" <> loan["id"]}
                          phx-submit="recast"
                          phx-hook="LoanAmount"
                          data-max={recast_max}
                          class="min-w-0 flex-[1_1_16rem] space-y-2"
                        >
                          <input type="hidden" name="request_id" value={@request_id} />
                          <input type="hidden" name="loan" value={loan["id"]} />
                          <input
                            type="range"
                            aria-label="Recast payment in $10,000 steps"
                            min={div(recast_min, 10_000)}
                            max={ceil(recast_max / 10_000)}
                            step="1"
                            value={ceil(min(recast_max, max(recast_min, 10_000)) / 10_000)}
                            class="w-full accent-teal-500"
                          />
                          <div class="flex flex-wrap items-start gap-3">
                            <span :if={can_repay} class="text-slate-400">or</span>
                            <input
                              type="number"
                              name="amount"
                              aria-label="Recast payment in dollars"
                              min={recast_min}
                              max={recast_max}
                              value={min(recast_max, max(recast_min, 10_000))}
                              class="w-32 rounded bg-slate-800 p-2"
                            />
                            <button phx-disable-with="Recasting…" class="rounded border p-2">Recast loan</button>
                          </div>
                        </.form>
                      </div>
                      <p :if={can_recast} class="mt-2 text-sm">
                        Recast: pay accrued interest first, then principal. Smaller remaining installments, same payoff date and interest rate. Keep cash for trading.
                      </p>
                    </details>
                    <.form
                      :if={@view.private["finance"]["can_declare_bankruptcy"]}
                      for={%{}}
                      phx-submit="bankruptcy"
                    >
                      <input type="hidden" name="request_id" value={@request_id} />
                      <button
                        data-confirm="Declare bankruptcy? This closes your company, forfeits access to its assets, and starts a 20-minute world-clock cooldown before a new company starting with no cash or ships."
                        phx-disable-with="Declaring…"
                        class="rounded border border-red-500 p-2"
                      >Declare bankruptcy</button>
                    </.form>
                  </section>
                </section>
              </div>
            </details>
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
            <h2 :if={Application.get_env(:tijara_tides, :email_enabled, false)} class="text-xl">
              Sign in with email
            </h2>
            <.form
              :if={Application.get_env(:tijara_tides, :email_enabled, false)}
              for={%{}}
              action={~p"/email/request"}
              id="email-login-form"
              class="my-3 flex flex-wrap gap-2"
            >
              <input type="hidden" name="request_id" value={@request_id} />
              <input
                type="email"
                name="email"
                required
                maxlength="254"
                autocomplete="email"
                aria-label="Sign-in email"
                class="rounded bg-slate-800 p-2"
              />
              <button class="rounded border p-2">Email me a sign-in link</button>
            </.form>
            <details
              :if={Application.get_env(:tijara_tides, :email_enabled, false)}
              id="email-token-disclosure"
              phx-mounted={JS.ignore_attributes("open")}
              class="mb-4"
            >
              <summary class="cursor-pointer">Use an emailed token on this device</summary>
              <p class="my-2 text-sm text-slate-300">
                In the desktop app, copy the sign-in token from your email and paste it here. Do not use the email link in a browser first.
              </p>
              <.form
                for={%{}}
                action={~p"/email/open"}
                id="email-open-form"
                class="flex flex-wrap gap-2"
              >
                <input
                  name="email_link"
                  type="text"
                  spellcheck="false"
                  autocapitalize="none"
                  required
                  maxlength="2048"
                  autocomplete="off"
                  aria-label="Emailed sign-in token"
                  placeholder="Paste your sign-in token"
                  class="min-w-0 flex-1 rounded bg-slate-800 p-2"
                />
                <button class="rounded border p-2">Continue on this device</button>
              </.form>
            </details>
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
            :if={
              @view.private && !@view.private["company"] &&
                is_nil(@view.private["account"]["suspended_ms"])
            }
            class="mb-6 rounded-xl border border-slate-700 bg-slate-900 p-6"
          >
            <h2 class="text-xl">Name your company</h2>
            <p class="my-3 text-slate-300">
              Start with $0 and no ships. Borrow up to {money(@view.private["finance"]["limit"])} to buy ships and fund cargo and voyages. Interest accrues while the world runs; prior bankruptcies reduce your credit limit.
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
              <button
                disabled={@view.private["finance"]["restart_ms"] > @view.public["clock_ms"]}
                class="rounded bg-teal-600 px-4 py-2 disabled:opacity-40"
              >Establish company</button>
              <p :if={@view.private["finance"]["restart_ms"] > @view.public["clock_ms"]}>
                Replacement company available in {minutes(
                  @view.private["finance"]["restart_ms"] - @view.public["clock_ms"]
                )} active-world minutes.
              </p>
            </.form>
          </section>
          <section
            :if={@view.private && @view.private["account"]["suspended_ms"]}
            id="account-suspension"
            class="rounded border border-red-500 p-4"
          >
            <h2>Account suspended</h2>
            <p>
              Five bankruptcies within 112 active-world days trigger suspension. Aging out does not lift it. Your original sponsor must pledge at least $50,000 to reinstate you.
            </p>
            <p :if={not @view.private["guarantees"]["has_sponsor"]}>
              This account has no sponsor. Contact the operator; there is no automatic reinstatement.
            </p>
          </section>
          <section
            :if={@view.private && @view.private["company"]}
            class="company-summary"
          >
            <div>
              <h2 class="text-2xl">{@view.private["company"]["name"]}</h2>
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
                    <div class="flex flex-wrap gap-3">
                      <form
                        id="port-selector"
                        phx-change="port"
                        phx-hook="PortSelector"
                        phx-update="ignore"
                        data-selected={@selected_port}
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
                    <details
                      id="about-port"
                      phx-mounted={JS.ignore_attributes("open")}
                      class="my-2 text-sm text-slate-400"
                    >
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
                        GameQueries.destination_options(@definitions, @view, @ship, @selected_port) %>
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
                    <% comparison_port =
                      if @ship && @ship["status"] == "sailing",
                        do: @ship["destination"],
                        else: @destination %>
                    <% compare_destination =
                      @port_market_side == "buy" && @ship && is_binary(comparison_port) &&
                        comparison_port != @selected_port &&
                        @definitions.catalogue["ports"][comparison_port] %>
                    <p
                      :if={compare_destination}
                      id="destination-market-note"
                      class="mb-3 text-xs text-slate-400"
                    >
                      Destination bids: {comparison_port}. Gross profit excludes handling and voyage costs; demand and prices may change before arrival.
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
                        GameQueries.purchase_voyage(
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
                      Choose a destination port before buying.
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
                              if compare_destination,
                                do: @view.markets[comparison_port <> "|" <> good] %>
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
                                  )} gross profit / lot
                                </span>
                                <% profit_lots =
                                  if selected_ship_here,
                                    do:
                                      min(
                                        Map.get(@trade_quantities, {"buy", good}, 0),
                                        destination_quote["demand"]
                                      ),
                                    else: 0 %>
                                <span
                                  :if={profit_lots > 0}
                                  class={[
                                    "destination-profit block",
                                    if(destination_quote["bid"] >= q["ask"],
                                      do: "text-teal-300",
                                      else: "text-red-400"
                                    )
                                  ]}
                                >
                                  {money((destination_quote["bid"] - q["ask"]) * profit_lots)} gross on {profit_lots} lots
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
                                  GameQueries.trade_freshness(
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
                                  <% total = GameQueries.purchase_total(q, @ship, item, quantity) %>
                                  <% voyage =
                                    GameQueries.purchase_voyage(
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
                  <aside
                    :if={@inspected_ship && @view.public["ships"][@inspected_ship]}
                    id="map-ship-overlay"
                    aria-label="Selected ship"
                    class="map-ship-overlay"
                  >
                    <% inspected = @view.public["ships"][@inspected_ship] %>
                    <% own = @view.private && @view.private["ships"][@inspected_ship] %>
                    <button
                      type="button"
                      phx-click="close-map-ship"
                      aria-label="Dismiss ship information"
                      class="float-right ml-3 rounded px-2 py-1 text-slate-300"
                    >✕</button>
                    <h2 class="text-base font-semibold text-teal-200">{inspected["name"]}</h2>
                    <p>{@view.public["companies"][inspected["company_id"]]["name"]}</p>
                    <p
                      :if={@view.public["companies"][inspected["company_id"]]["bankruptcy_ms"] != nil}
                      class="text-red-300"
                    >
                      Company in bankruptcy — assets in receivership
                    </p>
                    <p>{@definitions.classes[inspected["class"]]["name"]} · {inspected["status"]}</p>
                    <p>
                      {inspected["port"]}<span :if={inspected["destination"]}> → {inspected[
                        "destination"
                      ]}</span>
                    </p>
                    <p :if={inspected["status"] in ["sailing", "loading", "unloading"]}>
                      {minutes(max(0, inspected["arrive_ms"] - @view.public["clock_ms"]))} min remaining
                    </p>
                    <div :if={own} class="mt-2 border-t border-slate-600 pt-2">
                      <p class="font-semibold">Cargo aboard</p>
                      <p :if={own["cargo"] == []} class="text-slate-400">Empty hold</p>
                      <table :if={own["cargo"] != []} class="w-full" aria-label="Selected ship cargo">
                        <thead>
                          <tr>
                            <th class="text-left">Cargo</th><th class="text-right">Lots</th>
                          </tr>
                        </thead>
                        <tbody>
                          <tr :for={row <- manifest(own["cargo"])}>
                            <td>{cargo_name(row["good"])}</td><td class="text-right tabular-nums">
                              {row["quantity"]}
                            </td>
                          </tr>
                        </tbody>
                      </table>
                    </div>
                  </aside>
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
                    <div class="rounded-xl border border-slate-700 bg-slate-900/70 p-4">
                      <div class="flex items-start justify-between gap-3">
                        <div class="min-w-0">
                          <h2 class="break-words text-lg font-semibold text-teal-200">
                            {inspected["name"]}
                          </h2>
                          <p class="mt-1 text-sm text-slate-400">
                            {@view.public["companies"][inspected["company_id"]]["name"]}
                          </p>
                        </div>
                        <button
                          type="button"
                          phx-click="close-map-ship"
                          aria-label="Dismiss ship information"
                          class="shrink-0 rounded px-2 py-1 text-slate-400 hover:bg-slate-800 hover:text-white"
                        >✕</button>
                      </div>
                      <div class="mt-3 flex flex-wrap items-center gap-2 text-xs">
                        <span class="rounded-full border border-slate-600 px-2 py-1 text-slate-300">{@definitions.classes[
                          inspected["class"]
                        ]["name"]}</span>
                        <span
                          :if={inspected["status"] != "sailing"}
                          class="rounded-full bg-teal-950 px-2 py-1 capitalize text-teal-200"
                        >{inspected[
                          "status"
                        ]}</span>
                      </div>
                      <p
                        :if={
                          @view.public["companies"][inspected["company_id"]]["bankruptcy_ms"] != nil
                        }
                        class="mt-3 rounded border border-red-900 bg-red-950/40 p-2 text-sm text-red-300"
                      >
                        Company in bankruptcy — assets in receivership
                      </p>
                      <div class="mt-3 border-t border-slate-700 pt-3">
                        <p class="mb-1 text-xs text-slate-400">
                          {if inspected["destination"], do: "Route", else: "Port"}
                        </p>
                        <p class="flex flex-wrap items-center gap-2 text-sm font-medium">
                          <span>{inspected["port"]}</span>
                          <span :if={inspected["destination"]} aria-label="to" class="text-teal-400">→</span>
                          <span :if={inspected["destination"]}>{inspected["destination"]}</span>
                        </p>
                      </div>
                    </div>
                  </section>
                  <section :if={@view.private && @view.private["company"]} class="my-6">
                    <h2 class="mb-3 text-xl font-semibold">Your fleet</h2>
                    <details
                      id="shipyard"
                      phx-mounted={JS.ignore_attributes("open")}
                      open={map_size(@view.private["ships"]) == 0}
                      class="mb-3 rounded border border-slate-600 p-3"
                    >
                      <summary class="cursor-pointer">Buy a ship at {@selected_port}</summary>
                      <p class="my-2 text-sm">
                        Choose a port in the Ports panel to buy there. Ships arrive immediately, empty and docked. Keep cash for cargo, fuel and crew.
                      </p>
                      <button
                        type="button"
                        phx-click={
                          JS.set_attribute({"open", ""}, to: "#company-menu")
                          |> JS.push("report-close")
                        }
                        class="mb-2 rounded border border-teal-600 px-3 py-1"
                      >Arrange a loan</button>
                      <.form
                        :for={{class, spec} <- Enum.sort(@definitions.classes)}
                        for={%{}}
                        id={"shipyard-" <> class}
                        phx-submit="purchase-ship"
                        class="my-2 flex flex-wrap items-center justify-between gap-2"
                      >
                        <input type="hidden" name="request_id" value={@request_id} />
                        <input type="hidden" name="class" value={class} />
                        <input type="hidden" name="price_limit" value={spec["price"]} />
                        <span>{spec["name"]} · {money(spec["price"])}<br /><small>{div(
                          spec["weight"],
                          1000
                        )} tonnes · {div(spec["volume"], 1000)} m³ capacity</small></span>
                        <button
                          disabled={
                            spec["price"] >
                              @view.private["company"]["cash"] - @view.private["company"]["reserved"]
                          }
                          phx-disable-with="Buying…"
                          class="rounded bg-teal-700 px-3 py-1 disabled:opacity-40"
                        >Buy ship</button>
                      </.form>
                    </details>

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
                      <% ship_value = GameQueries.ship_sale_value(@ship, @view.public["clock_ms"]) %>
                      <p class="text-sm">
                        Book value: {finance_money(ship_value.book)}
                        <span class="ml-2 text-xs text-slate-400">Depreciates over 28 active-world days to 20% of build value.</span>
                      </p>
                      <details
                        :if={@ship["status"] != "sailing"}
                        id={"shipyard-offer-" <> @ship["id"]}
                        phx-mounted={JS.ignore_attributes("open")}
                        class="my-2"
                      >
                        <summary class="cursor-pointer">Shipyard offer</summary>
                        <.form
                          :if={@ship["status"] == "docked" && @ship["cargo"] == []}
                          for={%{}}
                          id="sell-ship-form"
                          phx-submit="sell-ship"
                          class="my-2 flex items-center gap-3"
                        >
                          <input type="hidden" name="request_id" value={@request_id} />
                          <input type="hidden" name="ship" value={@ship["id"]} />
                          <input type="hidden" name="minimum" value={ship_value.proceeds} />
                          <button
                            type="submit"
                            class="rounded border px-3 py-1"
                            phx-disable-with="Selling…"
                            data-confirm="Sell this ship to the shipyard? The ship will leave your fleet."
                          >Sell ship for {finance_money(ship_value.proceeds)}</button>
                          <span class="text-xs text-slate-400">90% of book value.</span>
                        </.form>
                      </details>
                      <h3 class="mt-4 mb-2 text-lg font-semibold">{@ship["name"]} — Manifest</h3>
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
                                    {"average_cost", "Avg. cost"},
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
                                  {div(max(0, b["expires_ms"] - @view.public["clock_ms"]), 60_000)} min
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
                        <.voyage_freshness
                          id={"preview-freshness-" <> @ship["id"]}
                          estimates={@preview["freshness"]}
                        />
                      </div>
                      <.voyage_freshness
                        id={"voyage-freshness-" <> @ship["id"]}
                        estimates={@view.private["voyage_freshness"][@ship["id"]]}
                      />
                      <details
                        :if={instruction_port(@ship, @destination, @definitions) != nil}
                        id={"instructions-" <> @ship["id"]}
                        phx-mounted={JS.ignore_attributes("open")}
                        class="mt-4 rounded border border-slate-700 p-3"
                      >
                        <summary class="cursor-pointer font-semibold">
                          Next port cargo instructions
                        </summary>
                        <p class="my-2 text-sm text-slate-400">
                          Execute when berthed. Sales unload before purchases load. Partial fills retry while waiting; sailing cancels any remainder. Prices are per lot, excluding handling. A purchase cap includes all purchase costs and does not reserve cash.
                        </p>
                        <% visit_port = instruction_port(@ship, @destination, @definitions) %>
                        <% instruction =
                          GameQueries.instruction_editor(
                            @definitions,
                            @ship,
                            Map.get(@instruction_drafts, @ship["id"], %{}),
                            @view.markets,
                            visit_port,
                            @view.private["company"]
                          ) %>
                        <% duplicate_sell =
                          instruction.side == "sell" &&
                            Enum.any?(@view.private["ship_instructions"], fn {_, order} ->
                              order["ship_id"] == @ship["id"] && order["good"] == instruction.good &&
                                order["side"] == "sell" && order["status"] in ["planned", "waiting"]
                            end) %>

                        <% visits = GameQueries.instruction_visits(@view.private, @ship["id"]) %>
                        <% visits =
                          if visit_port, do: Map.put_new(visits, visit_port, []), else: visits %>
                        <% onwards =
                          GameQueries.instruction_onwards(@view.private, @ship["id"], visit_port) %>

                        <p :if={is_nil(visit_port)} class="my-3 text-sm text-amber-200">
                          Choose a destination in the voyage controls before adding instructions.
                        </p>
                        <.form
                          :if={visit_port != nil}
                          for={%{}}
                          id={"instruction-form-" <> @ship["id"]}
                          phx-submit="add-instruction"
                          phx-change="edit-instruction"
                          class="grid grid-cols-2 gap-2 text-sm"
                        >
                          <input type="hidden" name="request_id" value={@request_id} />
                          <p class="col-span-2 font-semibold">Instructions at {visit_port}</p>
                          <label>
                            Action
                            <select
                              name="side"
                              aria-label="Instruction action"
                              class="block w-full rounded bg-slate-800 p-2"
                            ><option
                              value="sell"
                              selected={
                                instruction_value(@instruction_drafts, @ship, "side", "sell") ==
                                  "sell"
                              }
                            >
                              Sell
                            </option><option
                              value="buy"
                              selected={
                                instruction_value(@instruction_drafts, @ship, "side", "sell") == "buy"
                              }
                            >
                              Buy
                            </option></select>
                          </label>
                          <label>
                            Cargo
                            <select
                              name="good"
                              aria-label="Instruction cargo"
                              disabled={instruction.goods == []}
                              class="block w-full rounded bg-slate-800 p-2"
                            >
                              <option :if={instruction.goods == []} value="">
                                No cargo available
                              </option>
                              <option
                                :for={{good, _item} <- instruction.goods}
                                value={good}
                                selected={good == instruction.good}
                              >
                                {cargo_name(good)}
                              </option>
                            </select>
                          </label>
                          <label
                            id={"instruction-quantity-" <> @ship["id"]}
                            phx-hook="TradeQuantity"
                            data-max={instruction.maximum}
                            data-quantity={instruction.quantity}
                          >Target lots<input
                            name="quantity"
                            aria-label="Instruction target lots"
                            type="number"
                            min={if instruction.maximum < 1, do: 0, else: 1}
                            max={instruction.maximum}
                            disabled={instruction.maximum < 1}
                            value={instruction.quantity}
                            required
                            class="block w-full rounded bg-slate-800 p-2"
                          /></label>
                          <label>Limit price ($/lot)<input
                            name="limit"
                            aria-label="Instruction limit price"
                            type="number"
                            min="0"
                            max="10000000000"
                            value={instruction.limit}
                            step="0.01"
                            required
                            class="block w-full rounded bg-slate-800 p-2"
                          /></label>
                          <label>Purchase cap ($; buys only)<input
                            name="budget"
                            aria-label="Instruction purchase cap"
                            disabled={
                              instruction_value(@instruction_drafts, @ship, "side", "sell") == "sell"
                            }
                            type="number"
                            min="1"
                            max="10000000000"
                            value={instruction.budget}
                            class="block w-full rounded bg-slate-800 p-2 disabled:cursor-not-allowed disabled:opacity-50"
                          /></label>
                          <input
                            type="hidden"
                            name="onward"
                            value={if length(onwards) == 1, do: hd(onwards), else: ""}
                          />
                          <p
                            :if={instruction.side == "buy" and length(onwards) != 1}
                            class="col-span-2 text-amber-200"
                          >
                            Save an onward destination below before adding buy instructions.
                          </p>
                          <p :if={duplicate_sell} class="col-span-2 text-amber-200">
                            An active sell instruction already exists for this cargo. Cancel it before adding another.
                          </p>
                          <button
                            phx-disable-with="Adding…"
                            disabled={
                              duplicate_sell or instruction.maximum < 1 or is_nil(instruction.good) or
                                (instruction.side == "buy" and length(onwards) != 1)
                            }
                            class="self-end rounded bg-teal-700 p-2 disabled:cursor-not-allowed disabled:opacity-50"
                          >Add instruction</button>
                        </.form>
                        <div
                          :for={order <- ship_instructions(@view.private, @ship["id"])}
                          id={"instruction-" <> order["id"]}
                          class="mt-3 border-t border-slate-700 pt-2 text-sm"
                        >
                          <p>
                            <strong>{String.capitalize(order["side"])} {cargo_name(order["good"])}</strong>
                            at {order["port"]} · {order["filled"]}/{order["quantity"]} lots · {if order[
                                                                                                    "side"
                                                                                                  ] ==
                                                                                                    "buy",
                                                                                                  do:
                                                                                                    "maximum",
                                                                                                  else:
                                                                                                    "minimum"} {money(
                              order["limit"]
                            )}/lot
                          </p>
                          <p :if={order["side"] == "buy"}>
                            {money(order["spent"])} spent / {money(order["budget"])} cap
                          </p>
                          <p>{String.capitalize(order["status"])} · {order["reason"]}</p>
                          <button
                            :if={order["status"] in ["planned", "waiting"]}
                            phx-click="cancel-instruction"
                            phx-value-id={order["id"]}
                            class="mt-1 rounded border border-slate-500 px-2 py-1"
                          >Cancel order</button>
                        </div>
                        <p class="my-2 text-sm text-slate-400">
                          Plan an onward destination with or without cargo orders. Departure is manual unless automatic departure is enabled for this visit.
                        </p>
                        <.form
                          :for={
                            {shared_port, shared_onwards} <-
                              Enum.sort(visits)
                          }
                          for={%{}}
                          id={"visit-onward-" <> @ship["id"] <> "-" <> shared_port}
                          phx-submit="instruction-onward"
                          class="mb-3 space-y-2 text-sm"
                        >
                          <input type="hidden" name="port" value={shared_port} />
                          <input type="hidden" name="request_id" value={@request_id} />
                          <label>
                            Onward destination after {shared_port}
                            <select
                              name="onward"
                              aria-label="Shared onward port"
                              class="block w-full rounded bg-slate-800 p-2"
                            >
                              <option :if={shared_onwards == []} value="">
                                Choose onward destination
                              </option>
                              <option :if={length(shared_onwards) > 1} value="">
                                Resolve conflicting destinations
                              </option>
                              <option
                                :for={
                                  port <-
                                    Enum.sort(Map.keys(@definitions.catalogue["ports"])) --
                                      [shared_port]
                                }
                                value={port}
                                selected={shared_onwards == [port]}
                              >
                                {port}
                              </option>
                            </select>
                          </label>
                          <input type="hidden" name="auto_depart" value="false" />
                          <label class="flex items-center gap-2">
                            <input
                              type="checkbox"
                              name="auto_depart"
                              value="true"
                              checked={
                                get_in(@view.private, [
                                  "visit_plans",
                                  @ship["id"] <> "|" <> shared_port,
                                  "auto_depart"
                                ]) == true
                              }
                            /> Depart automatically after orders and handling finish
                          </label>
                          <p class="text-xs text-slate-400">
                            Waits for every order to be filled or cancelled and for sufficient sailing funds. Save to apply.
                          </p>
                          <p
                            :if={
                              get_in(@view.private, [
                                "visit_plans",
                                @ship["id"] <> "|" <> shared_port,
                                "departure_wait"
                              ])
                            }
                            class="text-amber-300"
                          >
                            {get_in(@view.private, [
                              "visit_plans",
                              @ship["id"] <> "|" <> shared_port,
                              "departure_wait"
                            ])}
                          </p>
                          <p :if={length(shared_onwards) > 1} class="text-amber-300">
                            Existing buy instructions disagree. Purchases are paused until you choose one onward port.
                          </p>
                          <button
                            phx-disable-with="Updating…"
                            class="rounded border border-slate-500 px-2 py-1"
                          >Save onward destination</button>
                        </.form>
                      </details>
                    </div>
                  </section>
                </div>
              </section>
              <section id="cargo-panel" class="workspace-panel" aria-label="Cargo">
                <h2 class="panel-title">Cargo</h2>
                <div class="panel-content" tabindex="0" aria-label="Cargo markets">
                  <section id="cargo-markets" class="my-6 rounded-xl border border-slate-700 p-5">
                    <div class="space-y-3">
                      <details
                        id="cargo-market-help"
                        phx-mounted={JS.ignore_attributes("open")}
                        class="mb-3 text-sm text-slate-400"
                      >
                        <summary class="cursor-pointer">About cargo markets</summary>
                        <p class="mt-2">
                          Supply and demand in lots · prices per lot, before handling · updated live. Cargo choices show the highest available bid and lowest available ask; — means no market on that side. Select a port to inspect its market.
                        </p>
                      </details>
                      <form
                        :if={@ship}
                        id="cargo-ship-filter"
                        phx-change="cargo-filter-ship"
                        class="mt-2 text-sm"
                      >
                        <label class="flex items-center gap-2">
                          <input type="hidden" name="compatible" value="false" />
                          <input
                            type="checkbox"
                            name="compatible"
                            value="true"
                            checked={@cargo_filter_ship}
                          /> Show only cargo carried by {@definitions.classes[@ship["class"]]["name"]}
                        </label>
                      </form>
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
                      class="mt-2 flex items-start gap-3 text-sm"
                    >
                      <label class="flex shrink-0 items-center gap-2 whitespace-nowrap">
                        <input type="hidden" name="roi" value="false" />
                        <input type="checkbox" name="roi" value="true" checked={@cargo_sort_roi} />
                        Sort by ROI
                      </label>
                      <p class="text-xs leading-5 text-slate-400">
                        Highest first: (best bid − best ask) ÷ best ask, before handling and voyage costs.
                      </p>
                    </form>
                    <p class="mt-2 mb-2 text-xs text-slate-400">
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
