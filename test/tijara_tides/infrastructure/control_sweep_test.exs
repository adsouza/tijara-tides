defmodule TijaraTides.Infrastructure.ControlSweepTest do
  @moduledoc """
  Every command control the interface renders is submitted as rendered and must commit.

  The unit is a control, not an action: a form is identified by the literal
  prefix of its template id and the action (and route operation) a given submit
  button sends; a click by its template id prefix, event, action, operation and
  `phx-value-*` keys. The required set comes from `TijaraTides.FormFields`, so a
  new button cannot escape the sweep, and two controls that send the same action
  are each pressed. Scenarios reach each control's state through legal commands
  only; a unit no scenario renders must be excluded below with the reason it
  cannot be reached. Every rendered instance is submitted in its own world, and
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

  # Units unreachable through legal commands, each with the reason and the shortest paths
  # tried. Both earlier entries (guarantee pledges, berth-queue cancellation) turned out
  # reachable once probed, and one hid a duplicate DOM id.
  @excluded %{}

  @scenarios ~w(base destination port_destination preview instruction queued sailing loading arrived exchange loan insolvent
                route route_edit route_running route_waiting route_paused reservation renewal
                luxury_open luxury_bid luxury_won luxury_award luxury_consigned no_company email
                queued_trade guarantee_candidate)a

  # {unit, scenario, instance} triples where the domain rightly refuses a rendered,
  # enabled control, as {reason, why the interface cannot avoid offering it}.
  @expected %{}

  setup_all do
    Sql.repo()
  end

  test "every rendered command control commits when submitted as rendered" do
    facts = FormFields.handler_facts()
    {required, prefixes} = inventory(facts)

    # "scenario:id-prefix" focuses a run (mutation audit, debugging): one scenario renders
    # and only units with that id prefix are pressed. Coverage needs the full run.
    focus =
      case System.get_env("TIJARA_CONTROL_SWEEP_FOCUS") do
        nil ->
          nil

        value ->
          [scenario, prefix] = String.split(value, ":", parts: 2)
          {String.to_existing_atom(scenario), prefix}
      end

    scenarios = if focus, do: [elem(focus, 0)], else: @scenarios
    assert scenarios -- @scenarios == [], "Unknown scenarios #{inspect(scenarios -- @scenarios)}"

    # Discovery: every scenario in which each control unit renders enabled.
    rendered =
      for scenario <- scenarios, reduce: %{} do
        acc ->
          scenario
          |> rendered_instances(facts, prefixes)
          |> Enum.filter(fn {unit, _instance} ->
            is_nil(focus) or elem(unit, 1) == elem(focus, 1)
          end)
          |> Enum.reduce(acc, fn {unit, instance}, acc ->
            Map.update(acc, unit, [{scenario, instance}], &(&1 ++ [{scenario, instance}]))
          end)
      end

    if System.get_env("TIJARA_CONTROL_SWEEP_DISCOVERY") do
      for {unit, scenarios} <- Enum.sort(rendered),
          do: IO.puts("#{inspect(unit)} <- #{inspect(scenarios)}")

      IO.puts("missing: #{inspect(Enum.sort(MapSet.to_list(required) -- Map.keys(rendered)))}")
    end

    unexpected = Map.keys(rendered) -- MapSet.to_list(required)
    assert unexpected == [], "Rendered controls missing from the static inventory"

    if focus do
      assert rendered != %{}, "Focus #{inspect(focus)} renders no control"
    else
      missing = required |> MapSet.difference(MapSet.new(Map.keys(rendered))) |> MapSet.to_list()

      assert Enum.sort(missing -- Map.keys(@excluded)) == [],
             "Controls no scenario renders: #{inspect(missing -- Map.keys(@excluded))}"

      stale =
        for unit <- Map.keys(@excluded),
            unit in Map.keys(rendered) or unit not in required,
            do: unit

      assert stale == [], "Exclusions that are now reachable or no longer exist"
    end

    # Repeated components share a static unit, but every instance must succeed.
    pairs =
      for {unit, instances} <- Enum.sort(rendered),
          {scenario, instance} <- instances,
          do: {unit, scenario, instance}

    unless focus do
      stale = Map.keys(@expected) -- pairs
      assert stale == [], "Expected rejections for pairs that no longer render: #{inspect(stale)}"
    end

    failures =
      for {unit, scenario, instance} <- pairs, reduce: [] do
        acc ->
          case submit(unit, scenario, instance, facts, prefixes) do
            :ok -> acc
            failure -> [{unit, scenario, instance, failure} | acc]
          end
      end

    assert Enum.reverse(failures) == []
  end

  defp rendered_instances(scenario, facts, prefixes) do
    Sql.with_world(fn c ->
      ctx = build(scenario, c)
      # Entity IDs differ between worlds; per-unit DOM ordinals identify each
      # occurrence across discovery and replay without trusting the first match.
      {units, _counts} =
        ctx
        |> render_controls(facts, prefixes)
        |> Enum.map_reduce(%{}, fn control, counts ->
          instance = Map.get(counts, control.unit, 0)
          {{control.unit, instance}, Map.put(counts, control.unit, instance + 1)}
        end)

      stop(ctx)
      units
    end)
  end

  # -- required inventory ---------------------------------------------------

  # Every command control unit the templates can render, and their id prefixes.
  defp inventory(facts) do
    records = for r <- FormFields.forms(), fact = facts[r.event], fact.command?, do: {r, fact}

    prefixes =
      for {r, _} <- records do
        r.id_prefix || flunk("Give the command control at #{r.where} a literal id prefix")
      end

    shared =
      for {r, _} <- records, reduce: %{} do
        acc -> Map.update(acc, r.id_prefix, [r.where], &[r.where | &1])
      end

    for {prefix, [_, _ | _] = wheres} <- shared,
        do: flunk("Control id prefix #{prefix} is shared by #{inspect(wheres)}")

    # A nested prefix lets one control's rendered id match another's template.
    unique = Enum.uniq(prefixes)

    for a <- unique,
        b <- unique,
        a != b,
        String.starts_with?(b, a),
        do: flunk("Control id prefix #{inspect(a)} is a prefix of #{inspect(b)}")

    units =
      for {r, fact} <- records,
          action <- MapSet.union(r.actions, fact.actions),
          operation <- if(action == "route", do: r.operations, else: [nil]),
          into: MapSet.new() do
        case r.kind do
          :form ->
            {:form, r.id_prefix, action, operation}

          :click ->
            {:click, r.id_prefix, r.event, action, operation,
             r.fields |> MapSet.to_list() |> Enum.sort()}
        end
      end

    {units, Enum.uniq(prefixes)}
  end

  defp prefix(id, prefixes) do
    prefixes
    |> Enum.filter(&(is_binary(id) and String.starts_with?(id, &1)))
    |> Enum.max_by(&String.length/1, fn -> nil end)
  end

  defp unit(%{kind: :form, id: id, key: {_event, action, operation}}, prefixes),
    do: {:form, prefix(id, prefixes), action, operation}

  defp unit(%{kind: :click, id: id, key: {event, action, operation}, values: values}, prefixes),
    do:
      {:click, prefix(id, prefixes), event, action, operation,
       values |> Map.keys() |> Enum.sort()}

  # -- submission -----------------------------------------------------------

  defp submit(unit, scenario, instance, facts, prefixes) do
    Sql.with_world(fn c ->
      ctx = build(scenario, c)

      control =
        ctx
        |> render_controls(facts, prefixes)
        |> Enum.filter(&(&1.unit == unit))
        |> Enum.fetch!(instance)

      before = :sys.get_state(c.server).game.revision

      {_, outcomes} = ControlSweep.outcomes(fn -> press(ctx, control) end)
      game = :sys.get_state(c.server).game
      stop(ctx)

      expected = @expected[{unit, scenario, instance}]

      cond do
        expected ->
          if outcomes == [{:error, elem(expected, 0)}],
            do: :ok,
            else: {:expected, expected, outcomes}

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

  defp press(ctx, %{kind: :click, id: id}),
    do: ctx.view |> element("[id='#{id}']") |> render_click()

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

  defp inputs(_key, _ctx), do: %{}

  # A required select left on an empty placeholder takes its first real option, as a
  # player must. Optional selects keep their empty choice, which means "none".
  defp placeholder_choices(html, id) do
    for select <-
          html |> LazyHTML.from_fragment() |> LazyHTML.query("form[id='#{id}'] select[required]"),
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

  defp scenario(:destination, c),
    do: c |> base() |> Map.put(:clicks, [{"destination-picker-open", %{}}])

  defp scenario(:port_destination, c), do: c |> base() |> Map.put(:port, "Singapore")

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

  # The target exceeds cargo aboard plus owned stock; a below-market limit keeps
  # the remainder waiting after collection and handling, with no market purchase.
  defp scenario(:route_waiting, c) do
    ctx = route_stops(base(c))
    [first | _] = stops(ctx)
    command(ctx, "rule", Map.merge(route_rule(ctx, first), %{"limit" => 1, "quantity" => 20}))

    command(ctx, "start", %{
      "action" => "route",
      "ship" => ctx.ship,
      "operation" => "start",
      "auto_depart" => true
    })

    for _ <- 1..20,
        not Enum.any?(GameServer.snapshot(ctx.token, c.server).private["ship_instructions"], fn
          {id, order} -> String.starts_with?(id, "route:") and order["status"] == "waiting"
        end),
        do: Sql.advance(c.server, 60_000)

    assert Enum.any?(GameServer.snapshot(ctx.token, c.server).private["ship_instructions"], fn
             {id, order} -> String.starts_with?(id, "route:") and order["status"] == "waiting"
           end),
           "Route visit never reached a waiting order"

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

  # A second purchase while loading is queued as the ship's next trade. Selecting the
  # ship's port renders the queued-trade notice in both the port and fleet panels.
  defp scenario(:queued_trade, c) do
    ctx = base(c)

    buy = %{
      "action" => "buy",
      "ship" => ctx.ship,
      "good" => "lumber",
      "quantity" => 1,
      "limit" => 1_000_000,
      "destination" => "Singapore"
    }

    command(ctx, "load", buy)
    assert %{"queued" => true} = command(ctx, "queue", buy)
    Map.put(ctx, :port, "Jakarta")
  end

  # Five counted bankruptcies suspend an invitee, making them the sponsor's pending
  # guarantee candidate. Each round leases storage on borrowed cash, so cash falls
  # below liabilities and voluntary bankruptcy is allowed.
  defp scenario(:guarantee_candidate, c) do
    ctx = base(c)
    %{"code" => code} = command(ctx, "invite", %{"action" => "invite"})
    {:ok, %{"session" => invitee}} = GameServer.redeem(code, c.server)

    for round <- 1..5 do
      request = &"invitee-#{round}-#{&1}"
      form_after_cooldown(c, invitee, request.("company"), "Pledge #{round}")
      Sql.command(c, invitee, request.("loan"), %{"action" => "borrow", "amount" => 1_000_000})

      used =
        Map.get(
          GameServer.snapshot(invitee, c.server).public["warehouse_utilization"],
          "Jakarta|dry",
          0
        )

      Sql.command(c, invitee, request.("lease"), %{
        "action" => "warehouse_lease",
        "port" => "Jakarta",
        "storage" => "dry",
        "blocks" => 1,
        "days" => 1,
        "price" => Warehouse.quote(used, "dry", 1, 1)
      })

      Sql.command(c, invitee, request.("bankruptcy"), %{"action" => "bankruptcy"})
    end

    [candidate] = GameServer.snapshot(ctx.token, c.server).private["guarantees"]["pending"]
    assert candidate["enabled"], "Sponsor cannot fund the minimum pledge"
    ctx
  end

  # -- scenario helpers -----------------------------------------------------

  # Re-forms a company once the bankruptcy cooldown, or any longer restart delay, has passed.
  defp form_after_cooldown(c, token, request, name) do
    Enum.reduce_while(1..30, nil, fn _, _ ->
      case GameServer.command(token, request, %{"action" => "company", "name" => name}, c.server) do
        {:ok, reply} ->
          {:halt, reply}

        {:error, :bankruptcy_cooldown} ->
          Sql.advance(c.server, 60_000)
          {:cont, nil}
      end
    end) || flunk("Company formation stayed in cooldown")
  end

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
