defmodule TijaraTidesWeb.GameLive do
  use TijaraTidesWeb, :live_view
  alias TijaraTides.UseCases.{Game, GameQueries}
  import TijaraTidesWeb.GameUI.Presentation, except: [error_message: 1, ship_coordinates: 3]

  @impl true
  def mount(_params, session, socket) do
    token = session["account_token"]

    if connected?(socket) do
      :ok = Game.subscribe()

      if token do
        Game.connect(token)
        Process.send_after(self(), :world_heartbeat, 15_000)
      end
    end

    socket =
      assign(socket,
        token: token,
        browser_id: session["player_id"],
        page_title: "Your shipping company",
        definitions: Game.definitions(),
        selected_port: "Singapore",
        route_drafts: %{},
        report_open: false,
        report_data: nil,
        report_error: nil,
        report_selection: %{"period" => "quarter", "metric" => "profit", "index" => nil},
        map_region: nil,
        map_filters_open: false,
        map_ship_classes: MapSet.new(Map.keys(Game.definitions().classes)),
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
        request_id: Game.request_id(),
        preview: nil
      )

    {:ok, refresh(socket)}
  end

  @impl true
  def handle_info({:game_changed, _revision}, socket), do: {:noreply, refresh(socket)}

  def handle_info(:world_heartbeat, socket) do
    Game.connect(socket.assigns.token)
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
      case Game.email_request(
             socket.assigns.token,
             params["purpose"],
             params["email"],
             socket.assigns.request_id,
             socket.assigns.browser_id
           ) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(request_id: Game.request_id())
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

  def handle_event("route-edit-rule", %{"rule" => id}, socket) do
    rule = get_in(socket.assigns.view.private || %{}, ["route_rules", id])

    if rule && rule["ship_id"] == socket.assigns.selected_ship do
      draft =
        Map.merge(rule, %{
          "rule" => id,
          "limit" => :erlang.float_to_binary(rule["limit"] / 100, decimals: 2),
          "budget" => if(rule["budget"], do: to_string(div(rule["budget"], 100)), else: ""),
          "quantity" => to_string(rule["quantity"] || 1)
        })

      {:noreply,
       assign(socket, :route_drafts, Map.put(socket.assigns.route_drafts, rule["stop_id"], draft))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("route-edit-cancel", %{"stop" => stop}, socket) do
    {:noreply, assign(socket, :route_drafts, Map.delete(socket.assigns.route_drafts, stop))}
  end

  def handle_event("route-draft", params, socket) do
    key = params["stop"]

    if is_binary(key) and Map.has_key?(socket.assigns.view.private["route_stops"] || %{}, key) do
      {:noreply,
       assign(
         socket,
         :route_drafts,
         Map.put(
           socket.assigns.route_drafts,
           key,
           params
           |> Map.take(~w(rule side good quantity quantity_mode limit budget))
           |> Map.filter(fn {_, value} -> is_binary(value) and byte_size(value) <= 128 end)
         )
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("route", params, socket) do
    command =
      params
      |> Map.take(~w(operation port stop rule side good quantity_mode request_id))
      |> Map.merge(%{"action" => "route", "ship" => socket.assigns.selected_ship})

    command =
      case params["operation"] do
        op when op in ["add_rule", "update_rule"] ->
          Map.merge(command, %{
            "quantity" => report_number(params["quantity"]) || 0,
            "limit" =>
              if(is_binary(params["limit"]) and byte_size(params["limit"]) <= 32,
                do: instruction_cents(params["limit"]),
                else: -1
              ),
            "budget" =>
              if(params["budget"] in [nil, ""],
                do: nil,
                else: (report_number(params["budget"]) || 0) * 100
              )
          })

        op when op in ["start", "resume"] ->
          Map.put(command, "auto_depart", true)

        _ ->
          command
      end

    run(socket, command)
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
    preview = Game.preview(socket.assigns.token, socket.assigns.selected_ship, dest)
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
      case Game.preview(socket.assigns.token, ship["id"], destination) do
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

    case Game.command(socket.assigns.token, request, command) do
      {:ok, result} ->
        socket =
          if command["action"] == "route" && command["operation"] in ["add_rule", "update_rule"],
            do:
              assign(
                socket,
                :route_drafts,
                Map.delete(socket.assigns.route_drafts, command["stop"])
              ),
            else: socket

        socket = if result["code"], do: assign(socket, :invite_code, result["code"]), else: socket

        socket =
          if command["action"] in ["buy", "sell"],
            do: assign(socket, trade_quantities: %{}, trade_edited: MapSet.new()),
            else: socket

        {:noreply,
         socket
         |> assign(preview: nil, request_id: Game.request_id())
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
    case Game.reports(socket.assigns.token, socket.assigns.report_selection) do
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
    view = Game.snapshot(socket.assigns.token)

    if connected?(socket) do
      if view.private,
        do: Game.presence_attach(socket.assigns.browser_id),
        else: Game.presence_detach()
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
        do: Game.preview(socket.assigns.token, ship["id"], socket.assigns.destination)

    socket =
      if ship && is_nil(socket.assigns.selected_ship),
        do: assign(socket, :selected_port, ship["port"]),
        else: socket

    limits =
      GameQueries.trade_limits(
        view,
        ship,
        socket.assigns.destination,
        socket.assigns.definitions.catalogue
      )

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

  defdelegate error_message(reason), to: TijaraTidesWeb.GameUI.Presentation
  defdelegate ship_coordinates(ship, clock, catalogue), to: TijaraTidesWeb.GameUI.Presentation

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
            <TijaraTidesWeb.GameUI.AccountPanel.panel
              invite_code={@invite_code}
              request_id={@request_id}
              view={@view}
            />
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
              <TijaraTidesWeb.GameUI.PortsPanel.panel
                definitions={@definitions}
                destination={@destination}
                port_market_side={@port_market_side}
                preview={@preview}
                purchase_good={@purchase_good}
                request_id={@request_id}
                selected_port={@selected_port}
                ship={@ship}
                trade_limits={@trade_limits}
                trade_quantities={@trade_quantities}
                traffic_grouping={@traffic_grouping}
                view={@view}
              />
              <TijaraTidesWeb.GameUI.FleetPanel.panel
                definitions={@definitions}
                destination={@destination}
                fleet_status={@fleet_status}
                inspected_ship={@inspected_ship}
                instruction_drafts={@instruction_drafts}
                manifest_sort={@manifest_sort}
                map_filters_open={@map_filters_open}
                map_region={@map_region}
                map_ship_classes={@map_ship_classes}
                map_ships={@map_ships}
                map_show_others={@map_show_others}
                preview={@preview}
                request_id={@request_id}
                route_drafts={@route_drafts}
                selected_port={@selected_port}
                selected_ship={@selected_ship}
                ship={@ship}
                view={@view}
              />
              <TijaraTidesWeb.GameUI.CargoPanel.panel
                cargo_filter_ship={@cargo_filter_ship}
                cargo_menu_open={@cargo_menu_open}
                cargo_options={@cargo_options}
                cargo_roi_varies={@cargo_roi_varies}
                cargo_sort_roi={@cargo_sort_roi}
                definitions={@definitions}
                market_good={@market_good}
                market_sort={@market_sort}
                ship={@ship}
                view={@view}
              />
            </div>
          </div>
        </div>
      </main>
    </Layouts.app>
    """
  end
end
