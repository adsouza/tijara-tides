defmodule TijaraTides.Infrastructure.ControlSweepTest do
  @moduledoc """
  Every command control the interface renders is submitted as rendered and must commit.

  The unit is a control, not an action: a form is identified by the literal prefix of
  its template id and the action (and route operation) a given submit button sends; a
  click by its event, action, operation and `phx-value-*` keys. The required set comes
  from `TijaraTides.FormFields`, so a new button cannot escape the sweep, and two
  controls that send the same action are each pressed. Scenarios reach each control's
  state through legal commands only; a unit no scenario renders must be excluded below
  with the reason it cannot be reached. Each unit is submitted in its own world, and
  command telemetry must report exactly one commit.
  """
  use ExUnit.Case, async: false
  @moduletag :game_database
  @moduletag :control_sweep
  @moduletag timeout: 1_200_000
  import Phoenix.ConnTest, only: [recycle: 1, get: 2, get: 3, post: 2]
  import Phoenix.LiveViewTest
  @endpoint TijaraTidesWeb.Endpoint
  alias TijaraTides.{ControlSweep, FormFields, WebFormFixture}
  alias TijaraTides.SqlReplay, as: Sql
  alias TijaraTides.Infrastructure.GameServer
  alias TijaraTides.Domain.Warehouse
  alias TijaraTides.CommandFuzzer.Contracts

  # Unreachable through legal commands in a test world, with the reason.
  @excluded %{
    {:form, "guarantee-", "guarantee", nil} =>
      "A pending candidate is an invitee who is suspended or at the maximum bankruptcy rate.",
    {:click, "cancel-berth-trade", "cancel_berth_trade", nil, ["id"]} =>
      "A berth queue needs more ships at one port than its berths allow."
  }

  @scenarios ~w(base preview instruction queued sailing loading arrived exchange loan insolvent
                route route_edit route_running route_paused reservation renewal
                luxury_open luxury_bid luxury_won luxury_award luxury_consigned no_company email)a

  # Controls that render earlier than they can succeed use the scenario that holds their stock.
  @prefer %{{:form, "auction-consign-form-", "auction_consign", nil} => :luxury_won}

  setup_all do
    Sql.repo()
  end

  test "every rendered command control commits when submitted as rendered" do
    facts = FormFields.handler_facts()
    {required, prefixes} = inventory(facts)

    # Discovery: the first scenario in which each control unit renders enabled.
    rendered =
      for scenario <- @scenarios, reduce: %{} do
        acc ->
          scenario
          |> rendered_units(facts, prefixes)
          |> Enum.reduce(acc, &Map.put_new(&2, &1, scenario))
      end

    if System.get_env("TIJARA_CONTROL_SWEEP_DISCOVERY") do
      for {unit, scenario} <- Enum.sort(rendered), do: IO.puts("#{inspect(unit)} <- #{scenario}")
      IO.puts("missing: #{inspect(Enum.sort(MapSet.to_list(required) -- Map.keys(rendered)))}")
    end

    missing = required |> MapSet.difference(MapSet.new(Map.keys(rendered))) |> MapSet.to_list()
    assert Enum.sort(missing -- Map.keys(@excluded)) == [], "Controls no scenario renders"

    stale =
      for unit <- Map.keys(@excluded),
          unit in Map.keys(rendered) or unit not in required,
          do: unit

    assert stale == [], "Exclusions that are now reachable or no longer exist"

    unexpected = Map.keys(rendered) -- MapSet.to_list(required)
    assert unexpected == [], "Rendered controls missing from the static inventory"

    for {unit, scenario} <- @prefer,
        do:
          assert(
            unit in rendered_units(scenario, facts, prefixes),
            "#{inspect(unit)} does not render in #{scenario}"
          )

    failures =
      for {unit, scenario} <- Enum.sort(Map.merge(rendered, @prefer)), reduce: [] do
        acc ->
          case submit(unit, scenario, facts, prefixes) do
            :ok -> acc
            failure -> [{unit, scenario, failure} | acc]
          end
      end

    assert Enum.reverse(failures) == []
  end

  defp rendered_units(scenario, facts, prefixes) do
    Sql.with_world(fn c ->
      ctx = build(scenario, c)
      units = ctx |> render_controls(facts, prefixes) |> Enum.map(& &1.unit) |> Enum.uniq()
      stop(ctx)
      units
    end)
  end

  # -- required inventory ---------------------------------------------------

  # Every command control unit the templates can render, and the form id prefixes.
  defp inventory(facts) do
    records = for r <- FormFields.forms(), fact = facts[r.event], fact.command?, do: {r, fact}

    prefixes =
      for {%{kind: :form} = r, _} <- records do
        r.id_prefix || flunk("Give the command form at #{r.where} a literal id prefix")
      end

    shared =
      for {%{kind: :form} = r, _} <- records, reduce: %{} do
        acc -> Map.update(acc, r.id_prefix, [r.where], &Enum.uniq([r.where | &1]))
      end

    for {prefix, [_, _ | _] = wheres} <- shared,
        do: flunk("Form id prefix #{prefix} is shared by #{inspect(wheres)}")

    units =
      for {r, fact} <- records,
          action <- MapSet.union(r.actions, fact.actions),
          operation <- if(action == "route", do: r.operations, else: [nil]),
          into: MapSet.new() do
        case r.kind do
          :form ->
            {:form, r.id_prefix, action, operation}

          :click ->
            {:click, r.event, action, operation, r.fields |> MapSet.to_list() |> Enum.sort()}
        end
      end

    {units, Enum.uniq(prefixes)}
  end

  defp unit(%{kind: :form, id: id, key: {_event, action, operation}}, prefixes) do
    prefix =
      prefixes
      |> Enum.filter(&(is_binary(id) and String.starts_with?(id, &1)))
      |> Enum.max_by(&String.length/1, fn -> nil end)

    {:form, prefix, action, operation}
  end

  defp unit(%{kind: :click, key: {event, action, operation}, values: values}, _prefixes),
    do: {:click, event, action, operation, values |> Map.keys() |> Enum.sort()}

  # -- submission -----------------------------------------------------------

  defp submit(unit, scenario, facts, prefixes) do
    Sql.with_world(fn c ->
      ctx = build(scenario, c)
      control = ctx |> render_controls(facts, prefixes) |> Enum.find(&(&1.unit == unit))
      before = :sys.get_state(c.server).game.revision

      {_, outcomes} = ControlSweep.outcomes(fn -> press(ctx, control) end)
      game = :sys.get_state(c.server).game
      stop(ctx)

      cond do
        outcomes != [{:ok, nil}] ->
          {:outcomes, outcomes}

        game.revision != before + 1 ->
          {:revision, game.revision - before}

        true ->
          Sql.assert_rows(c, game)
          :ok
      end
    end)
  end

  defp press(ctx, %{kind: :click, event: event, values: values}),
    do: render_click(ctx.view, event, values)

  defp press(ctx, %{kind: :form, id: nil, unit: unit}),
    do: flunk("Give the #{inspect(unit)} form an id so it can be submitted (#{ctx.scenario})")

  defp press(ctx, %{kind: :form, id: id, submitter: submitter} = control) do
    selector = "[id='#{id}']"

    html = render(ctx.view)

    data =
      html
      |> required_fill(id)
      |> Map.merge(placeholder_choices(html, id))
      |> Map.merge(inputs(control.unit, ctx))

    ctx.view |> form(selector, data) |> render_submit(submitter)
  end

  # What a player must type before submitting, beyond required fields and placeholders.
  defp inputs({:form, "trade-", "buy", nil}, _ctx), do: %{"quantity" => "1"}

  defp inputs({:form, "auction-consign-form-", "auction_consign", nil}, ctx),
    do: %{"warehouse" => ctx.award, "good" => "whisky", "quantity" => "1"}

  defp inputs(_key, _ctx), do: %{}

  # A select left on an empty placeholder takes its first real option, as a player must.
  defp placeholder_choices(html, id) do
    for select <- html |> LazyHTML.from_fragment() |> LazyHTML.query("form[id='#{id}'] select"),
        [name] = LazyHTML.attribute(select, "name"),
        options = for(o <- LazyHTML.query(select, "option"), do: o),
        selected = Enum.filter(options, &(LazyHTML.attribute(&1, "selected") != [])),
        current = List.first(selected) || List.first(options),
        current && LazyHTML.attribute(current, "value") == [""],
        choice = Enum.find(options, &(LazyHTML.attribute(&1, "value") not in [[""], []])),
        choice,
        into: %{} do
      [value] = LazyHTML.attribute(choice, "value")
      {name, value}
    end
  end

  # Blank required fields get the smallest valid sample for their input type.
  defp required_fill(html, id) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("form[id='#{id}'] input[required]")
    |> Enum.flat_map(fn input ->
      [name] = LazyHTML.attribute(input, "name")

      case {LazyHTML.attribute(input, "value"), LazyHTML.attribute(input, "type")} do
        {[value], _} when value != "" -> []
        {_, ["number"]} -> [{name, input |> LazyHTML.attribute("min") |> min_sample()}]
        _ -> [{name, "Sweep #{System.unique_integer([:positive])}"}]
      end
    end)
    |> URI.encode_query()
    |> Plug.Conn.Query.decode()
  end

  defp min_sample([value]) when value not in ["", "0"], do: value
  defp min_sample(_), do: "1"

  defp render_controls(ctx, facts, prefixes) do
    # Selecting the ship refreshes synchronously; background refreshes are asynchronous.
    if ctx.ship, do: render_click(ctx.view, "ship", %{"id" => ctx.ship})
    if ctx[:port], do: render_click(ctx.view, "port", %{"id" => ctx.port})
    for {event, values} <- ctx[:clicks] || [], do: render_click(ctx.view, event, values)

    for control <- ControlSweep.controls(render(ctx.view), facts) do
      control = resolve(control, ctx)
      Map.put(control, :unit, unit(control, prefixes))
    end
  end

  # The sail control submits sail or reroute depending on whether the ship is at sea.
  defp resolve(%{key: {"sail", actions, nil}} = control, ctx) when is_list(actions) do
    status = GameServer.snapshot(ctx.token, ctx.c.server).private["ships"][ctx.ship]["status"]
    %{control | key: {"sail", if(status == "sailing", do: "reroute", else: "sail"), nil}}
  end

  defp resolve(control, _ctx), do: control

  defp stop(ctx), do: if(Process.alive?(ctx.view.pid), do: GenServer.stop(ctx.view.pid, :normal))

  # -- scenarios ------------------------------------------------------------

  defp build(scenario, c), do: scenario |> scenario(c) |> Map.put(:scenario, scenario)

  defp scenario(:base, c), do: base(c)

  defp scenario(:preview, c), do: c |> base() |> Map.put(:clicks, [preview("Singapore")])

  defp scenario(:instruction, c) do
    ctx = base(c)
    command(ctx, "instruction", instruction(ctx))
    Map.put(ctx, :clicks, [preview("Singapore")])
  end

  # Queues an automatic departure from the current port toward the planned destination.
  defp scenario(:queued, c) do
    ctx = scenario(:instruction, c)

    command(ctx, "queue", %{
      "action" => "instruction_onward",
      "ship" => ctx.ship,
      "port" => "Jakarta",
      "onward" => "Singapore",
      "auto_depart" => true
    })

    ctx
  end

  defp scenario(:sailing, c) do
    ctx = base(c)
    render_click(ctx.view, "ship", %{"id" => ctx.ship})
    render_click(ctx.view, "preview", %{"destination" => "Singapore"})

    command(ctx, "sail", %{
      "action" => "sail",
      "ship" => ctx.ship,
      "destination" => "Singapore",
      "fuel_limit" => 1_000_000_000
    })

    Map.put(ctx, :clicks, [preview("Jakarta")])
  end

  # Still loading a purchase, with a next port selected: departure can only be queued.
  defp scenario(:loading, c) do
    ctx = base(c)

    command(ctx, "load", %{
      "action" => "buy",
      "ship" => ctx.ship,
      "good" => "lumber",
      "quantity" => 1,
      "limit" => 1_000_000,
      "destination" => "Singapore"
    })

    status = GameServer.snapshot(ctx.token, c.server).private["ships"][ctx.ship]["status"]
    assert status == "loading", "Purchase handling already finished: #{status}"
    Map.put(ctx, :clicks, [preview("Singapore")])
  end

  # Docked at the cargo's destination with the market showing what the port buys.
  defp scenario(:arrived, c) do
    ctx = arrive(base(c))

    for _ <- 1..20,
        GameServer.snapshot(ctx.token, c.server).private["ships"][ctx.ship]["status"] != "docked",
        do: Sql.advance(c.server, 600_000)

    ctx
    |> Map.put(:port, "Singapore")
    |> Map.put(:clicks, [{"port-market-side", %{"side" => "sell"}}])
  end

  defp scenario(:exchange, c) do
    ctx = base(c)

    command(ctx, "order", %{
      "action" => "exchange_place",
      "warehouse" => ctx.f.warehouse,
      "good" => "lumber",
      "side" => "sell",
      "quantity" => 1,
      "price" => 1_000_000
    })

    command(ctx, "preset", Contracts.name_command(:preset, "Sweep"))
    Map.put(ctx, :clicks, [{"exchange-good", %{"good" => "lumber"}}])
  end

  defp scenario(:loan, c) do
    ctx = base(c)
    command(ctx, "loan", %{"action" => "borrow", "amount" => 1_000_000})
    ctx
  end

  # Spending more than unborrowed cash leaves liabilities above available cash.
  defp scenario(:insolvent, c) do
    ctx = base(c)
    command(ctx, "loan", %{"action" => "borrow", "amount" => 25_000_000})
    owned = ships(ctx)

    for n <- 1..20,
        GameServer.snapshot(ctx.token, c.server).private["finance"]["can_declare_bankruptcy"] !=
          true,
        do:
          GameServer.command(
            ctx.token,
            "hull-#{n}",
            %{
              "action" => "purchase_ship",
              "class" => "small_freighter",
              "port" => "Jakarta",
              "price_limit" => 1_000_000_000
            },
            c.server
          )

    # An empty, docked hull renders the sale form.
    [empty | _] = ships(ctx) -- owned
    %{ctx | ship: empty}
  end

  defp scenario(:route, c) do
    ctx = route_stops(base(c))
    [first | _] = stops(ctx)
    command(ctx, "rule", route_rule(ctx, first))
    ctx
  end

  defp scenario(:route_edit, c) do
    ctx = scenario(:route, c)
    [rule] = Map.keys(GameServer.snapshot(ctx.token, c.server).private["route_rules"])
    Map.put(ctx, :clicks, [{"route-edit-rule", %{"rule" => rule}}])
  end

  defp scenario(:route_running, c) do
    ctx = scenario(:route, c)

    command(ctx, "start", %{
      "action" => "route",
      "ship" => ctx.ship,
      "operation" => "start",
      "auto_depart" => true
    })

    ctx
  end

  defp scenario(:route_paused, c) do
    ctx = scenario(:route_running, c)
    command(ctx, "pause", %{"action" => "route", "ship" => ctx.ship, "operation" => "pause"})
    ctx
  end

  defp scenario(:reservation, c) do
    ctx = base(c)

    command(ctx, "reserve", %{
      "action" => "warehouse_reserve",
      "warehouse" => ctx.f.warehouse,
      "ship" => ctx.ship,
      "good" => "lumber",
      "quantity" => 1,
      "kind" => "stock"
    })

    ctx
  end

  # The one-day fixture lease enters its six-hour renewal window.
  defp scenario(:renewal, c) do
    ctx = base(c)
    lease = :sys.get_state(c.server).game.entities["warehouses"][ctx.f.warehouse]

    Sql.advance(
      c.server,
      lease["expires_ms"] - :sys.get_state(c.server).game.clock_ms - 3_600_000
    )

    ctx
  end

  defp scenario(:luxury_open, c) do
    ctx = base(c)
    {listing, _warehouse} = luxury_listing(ctx)
    Map.put(ctx, :port, listing["port"])
  end

  defp scenario(:luxury_bid, c) do
    ctx = base(c)
    {listing, warehouse} = luxury_listing(ctx)

    command(ctx, "bid", %{
      "action" => "auction_bid",
      "auction" => listing["id"],
      "warehouse" => warehouse,
      "price" => listing["reserve"]
    })

    Map.put(ctx, :port, listing["port"])
  end

  # Won whisky waiting in its award storage, ready to consign.
  defp scenario(:luxury_won, c) do
    ctx = base(c)
    {listing, warehouse} = luxury_listing(ctx)

    command(ctx, "bid", %{
      "action" => "auction_bid",
      "auction" => listing["id"],
      "warehouse" => warehouse,
      "price" => listing["reserve"]
    })

    Sql.advance(c.server, listing["closes_ms"] - :sys.get_state(c.server).game.clock_ms + 1)
    ctx |> Map.put(:port, listing["port"]) |> Map.put(:award, "award:" <> listing["id"])
  end

  # Won cargo whose award storage has expired but is still inside its grace period.
  defp scenario(:luxury_award, c) do
    ctx = base(c)
    {listing, warehouse} = luxury_listing(ctx)

    command(ctx, "bid", %{
      "action" => "auction_bid",
      "auction" => listing["id"],
      "warehouse" => warehouse,
      "price" => listing["reserve"]
    })

    Sql.advance(c.server, listing["closes_ms"] - :sys.get_state(c.server).game.clock_ms + 1)
    award = :sys.get_state(c.server).game.entities["warehouses"]["award:" <> listing["id"]]
    Sql.advance(c.server, award["expires_ms"] - :sys.get_state(c.server).game.clock_ms + 1)
    Map.put(ctx, :port, listing["port"])
  end

  defp scenario(:luxury_consigned, c) do
    ctx = base(c)
    {listing, warehouse} = luxury_listing(ctx)

    command(ctx, "bid", %{
      "action" => "auction_bid",
      "auction" => listing["id"],
      "warehouse" => warehouse,
      "price" => listing["reserve"]
    })

    Sql.advance(c.server, listing["closes_ms"] - :sys.get_state(c.server).game.clock_ms + 1)

    command(ctx, "consign", %{
      "action" => "auction_consign",
      "warehouse" => "award:" <> listing["id"],
      "good" => "whisky",
      "quantity" => 1,
      "price" => 1_000_000_000
    })

    Map.put(ctx, :port, listing["port"])
  end

  defp scenario(:no_company, c) do
    {conn, token} = WebFormFixture.session(c)
    {:ok, view, _} = conn |> recycle() |> live("/play")
    %{c: c, token: token, view: view, ship: nil, f: nil}
  end

  # Invitations need a verified address: request a link and redeem it through the routes.
  defp scenario(:email, c) do
    previous = Application.get_env(:tijara_tides, :email_enabled)
    Application.put_env(:tijara_tides, :email_enabled, true)
    on_exit(fn -> Application.put_env(:tijara_tides, :email_enabled, previous) end)
    {conn, token} = WebFormFixture.session(c)

    {:ok, _} =
      GameServer.email_request(
        token,
        "link",
        "sweep@example.test",
        "sweep-link",
        "client",
        c.server
      )

    [request] = Map.values(:sys.get_state(c.server).game.entities["email_requests"])
    link = GameServer.email_token(request["id"])
    prepared = conn |> recycle() |> get("/email/verify", %{"token" => link})
    confirmed = prepared |> recycle() |> post("/email/redeem")
    session = Plug.Conn.get_session(confirmed, :account_token)
    {:ok, view, _} = confirmed |> recycle() |> live("/play")
    %{c: c, token: session, view: view, ship: nil, f: nil}
  end

  # -- scenario helpers -----------------------------------------------------

  defp arrive(ctx) do
    render_click(ctx.view, "ship", %{"id" => ctx.ship})
    render_click(ctx.view, "preview", %{"destination" => "Singapore"})

    command(ctx, "sail", %{
      "action" => "sail",
      "ship" => ctx.ship,
      "destination" => "Singapore",
      "fuel_limit" => 1_000_000_000
    })

    ship = GameServer.snapshot(ctx.token, ctx.c.server).private["ships"][ctx.ship]
    Sql.advance(ctx.c.server, ship["arrive_ms"] - :sys.get_state(ctx.c.server).game.clock_ms + 1)
    ctx
  end

  defp base(c) do
    f = WebFormFixture.fixture(c)
    %{c: c, f: f, token: f.token, view: f.view, ship: f.ship}
  end

  defp command(ctx, request, payload),
    do: Sql.command(ctx.c, ctx.token, "sweep-" <> request, payload)

  defp preview(destination), do: {"preview", %{"destination" => destination}}

  defp ships(ctx), do: Map.keys(GameServer.snapshot(ctx.token, ctx.c.server).private["ships"])

  defp stops(ctx) do
    GameServer.snapshot(ctx.token, ctx.c.server).private["route_stops"]
    |> Map.values()
    |> Enum.sort_by(& &1["position"])
    |> Enum.map(& &1["id"])
  end

  defp instruction(ctx),
    do: %{
      "action" => "instruction",
      "ship" => ctx.ship,
      "port" => "Singapore",
      "side" => "sell",
      "good" => "lumber",
      "quantity" => 1,
      "limit" => 1
    }

  defp route_stops(ctx) do
    for port <- ["Jakarta", "Singapore"],
        do:
          command(ctx, "stop-" <> port, %{
            "action" => "route",
            "ship" => ctx.ship,
            "operation" => "add_stop",
            "port" => port
          })

    ctx
  end

  defp route_rule(ctx, stop),
    do: %{
      "action" => "route",
      "ship" => ctx.ship,
      "operation" => "add_rule",
      "stop" => stop,
      "side" => "buy",
      "good" => "lumber",
      "quantity" => 1,
      "limit" => 1_000_000
    }

  # Shortens the world auction cycle, leases dry storage at a world whisky listing's port
  # and waits for bidding to open.
  defp luxury_listing(ctx) do
    server = ctx.c.server

    :sys.replace_state(server, fn s ->
      %{
        s
        | catalogue:
            Map.put(s.catalogue, "auctions", %{"interval_ms" => 10_000, "window_ms" => 10_000})
      }
    end)

    Sql.advance(server, 1)
    public = GameServer.snapshot(ctx.token, server).public
    listing = Enum.find(public["auctions"], &(&1["good"] == "whisky" and is_nil(&1["seller"])))
    assert listing, "No world whisky listing"
    port = listing["port"]
    used = Map.get(public["warehouse_utilization"], port <> "|dry", 0)
    owned = Map.keys(GameServer.snapshot(ctx.token, server).private["warehouses"])

    command(ctx, "luxury-lease", %{
      "action" => "warehouse_lease",
      "port" => port,
      "storage" => "dry",
      "blocks" => 1,
      "days" => 3,
      "price" => Warehouse.quote(used, "dry", 1, 3)
    })

    [warehouse] = Map.keys(GameServer.snapshot(ctx.token, server).private["warehouses"]) -- owned
    Sql.advance(server, listing["opens_ms"] - :sys.get_state(server).game.clock_ms + 1)
    {listing, warehouse}
  end
end
