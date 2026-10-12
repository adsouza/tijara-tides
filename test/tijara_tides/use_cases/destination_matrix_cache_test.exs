defmodule TijaraTides.UseCases.DestinationMatrixCacheTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest, only: [render_component: 2]
  alias TijaraTides.Domain.{Markets, Visibility}
  alias TijaraTides.UseCases.{DestinationMatrixCache, GameQueries}
  alias TijaraTidesWeb.{GameLive, GameUI.DestinationPicker}

  setup do
    {state, catalogue} = TijaraTides.CommandFuzzer.fixture()

    catalogue =
      Map.put(catalogue, "ports", Map.take(catalogue["ports"], ["Singapore", "Colombo"]))

    catalogue = Map.put(catalogue, "routes", Map.take(catalogue["routes"], ["Singapore|Colombo"]))

    view = %{
      public: Visibility.public(state, catalogue),
      private: Visibility.private(state, state.entities["accounts"]["account"]),
      markets: Markets.quotes(state, catalogue)
    }

    ship = %{view.private["ships"]["company:1"] | "port" => "Singapore"}
    view = put_in(view, [:private, "ships", ship["id"]], ship)
    Code.ensure_loaded!(GameQueries)
    mfa = {GameQueries, :destination_matrix, 3}
    assert :erlang.trace_pattern(mfa, true, [:local, :call_count]) == 1
    on_exit(fn -> :erlang.trace_pattern(mfa, false, [:local, :call_count]) end)
    %{definitions: %{catalogue: catalogue}, view: view, ship: ship, mfa: mfa}
  end

  test "closed pickers defer work; unchanged inputs reuse one exact matrix", c do
    assert DestinationMatrixCache.refresh(nil, c.definitions, c.view, c.ship, false) == nil
    assert calls(c) == 0
    cache = DestinationMatrixCache.refresh(nil, c.definitions, c.view, c.ship, true)
    assert calls(c) == 1

    unrelated =
      c.view
      |> put_in([:public, "revision"], 123)
      |> put_in([:private, "notices"], [%{}])
      |> put_in([:private, "account", "locale"], "ar")

    for open <- [true, false, true] do
      assert DestinationMatrixCache.refresh(cache, c.definitions, unrelated, c.ship, open) ===
               cache
    end

    assert calls(c) == 1
    assert cache.matrix === GameQueries.destination_matrix(c.definitions, c.view, c.ship)
  end

  test "every planning dependency invalidates; open refreshes match uncached results", c do
    cache = DestinationMatrixCache.refresh(nil, c.definitions, c.view, c.ship, true)

    changes = [
      {put_in(c.definitions, [:catalogue, "routes", "Singapore|Colombo", "nautical_miles"], 2),
       c.view, c.ship},
      {c.definitions, put_in(c.view, [:public, "clock_ms"], 1), c.ship},
      {c.definitions, put_in(c.view, [:markets, "Colombo|lumber", "bid"], 20_000), c.ship},
      {c.definitions, put_in(c.view, [:private, "company", "cash"], 0), c.ship},
      {c.definitions, put_in(c.view, [:private, "company", "reserved"], 123), c.ship},
      {c.definitions, put_in(c.view, [:private, "company", "unpaid"], 1), c.ship},
      {c.definitions, put_in(c.view, [:private, "account", "id"], "another-owner"), c.ship},
      {c.definitions,
       put_in(c.view, [:private, "ships", "other"], Map.put(c.ship, "id", "other")), c.ship},
      {c.definitions,
       put_in(c.view, [:private, "ship_routes", c.ship["id"]], %{"protection" => "guards"}),
       c.ship},
      {c.definitions, c.view,
       Map.put(c.ship, "cargo", [%{"good" => "lumber", "quantity" => 1, "unit_cost" => 1}])},
      {c.definitions, c.view, Map.put(c.ship, "id", "selected-other")}
    ]

    for {definitions, view, ship} <- changes do
      assert DestinationMatrixCache.refresh(cache, definitions, view, ship, false) == nil
      before = calls(c)
      refreshed = DestinationMatrixCache.refresh(cache, definitions, view, ship, true)
      assert calls(c) == before + 1
      assert refreshed.matrix === GameQueries.destination_matrix(definitions, view, ship)
      assert refreshed.key != cache.key
    end

    assert DestinationMatrixCache.refresh(
             cache,
             c.definitions,
             %{c.view | private: nil},
             c.ship,
             true
           ) == nil

    assert DestinationMatrixCache.refresh(cache, c.definitions, c.view, nil, true) == nil

    assert DestinationMatrixCache.refresh(
             cache,
             c.definitions,
             c.view,
             Map.put(c.ship, "status", "sailing"),
             true
           ) == nil
  end

  test "numeric input types require a distinct cache entry", c do
    definitions =
      put_in(c.definitions, [:catalogue, "goods", "spices", "reference_cents"], 300_000)

    float_definitions =
      put_in(definitions, [:catalogue, "goods", "spices", "reference_cents"], 300_000.0)

    cache = DestinationMatrixCache.refresh(nil, definitions, c.view, c.ship, true)
    assert DestinationMatrixCache.refresh(cache, float_definitions, c.view, c.ship, false) == nil
    refreshed = DestinationMatrixCache.refresh(cache, float_definitions, c.view, c.ship, true)
    assert calls(c) == 2
    assert cache.matrix == refreshed.matrix
    refute cache.matrix === refreshed.matrix
    assert refreshed.matrix === GameQueries.destination_matrix(float_definitions, c.view, c.ship)
  end

  defp socket(c) do
    %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        destination_matrix_cache: nil,
        destination_matrix: nil,
        destination_geometry_cache: nil,
        destination_matrix_generation: 0,
        destination_matrix_running: false,
        destination_matrix_error: false,
        destination_picker_open: false,
        definitions: c.definitions,
        view: c.view,
        ship: c.ship,
        selected_ship: c.ship["id"],
        preferred_locale: nil,
        handling_focus_ship: nil,
        system_notices: [],
        first_ship_port_selected: false,
        selected_port: "Guangzhou",
        music_focus: nil,
        trade_context: nil,
        trade_quantities: %{},
        trade_edited: MapSet.new(),
        protection: "none",
        refresh_generation: 1,
        refresh_pending: false,
        dropdown_active: false
      }
    }
  end

  defp complete(socket, c) do
    result = DestinationMatrixCache.calculate(c.definitions, c.view, c.ship, nil)

    GameLive.handle_async(
      {:destination_matrix, socket.assigns.destination_matrix_generation},
      {:ok, result},
      socket
    )
  end

  test "opening and loading rendering do no synchronous planning; completed results are reused",
       c do
    {:noreply, opened} = GameLive.handle_event("destination-picker-open", %{}, socket(c))
    assert opened.assigns.destination_picker_open
    assert opened.assigns.destination_matrix_running
    assert opened.assigns.destination_matrix == nil
    assert calls(c) == 0

    html =
      render_component(&DestinationPicker.panel/1,
        definitions: c.definitions,
        view: c.view,
        ship: c.ship,
        matrix: nil
      )

    assert html =~ "destination-picker-loading"
    assert html =~ "Calculating trade estimates..."
    tree = LazyHTML.from_fragment(html)
    assert LazyHTML.query(tree, "#destination-matrix tbody tr") |> Enum.count() == 1
    assert LazyHTML.query(tree, "#destination-preview-Colombo") |> Enum.count() == 1
    refute html =~ "Insufficient voyage funds"
    refute html =~ "No trade opportunity"
    assert calls(c) == 0

    {:noreply, ready} = complete(opened, c)
    assert calls(c) == 1
    assert ready.assigns.destination_matrix != nil
    refute ready.assigns.destination_matrix_running
    {:noreply, closed} = GameLive.handle_event("destination-picker-close", %{}, ready)
    {:noreply, reopened} = GameLive.handle_event("destination-picker-open", %{}, closed)
    assert reopened.assigns.destination_matrix === ready.assigns.destination_matrix
    assert calls(c) == 1
  end

  test "connected opening launches a task and accepts its result", c do
    connected = %{socket(c) | transport_pid: self()}
    {:noreply, opened} = GameLive.handle_event("destination-picker-open", %{}, connected)
    assert opened.assigns.destination_matrix == nil
    generation = opened.assigns.destination_matrix_generation

    assert_receive {:phoenix, :async_result,
                    {:start, {_ref, nil, {:destination_matrix, ^generation}, {:ok, result}}}},
                   5000

    {:noreply, ready} =
      GameLive.handle_async({:destination_matrix, generation}, {:ok, result}, opened)

    assert ready.assigns.destination_matrix === elem(result, 0).matrix
  end

  test "world updates coalesce; obsolete completion retains geometry but never publishes estimates",
       c do
    {:noreply, opened} = GameLive.handle_event("destination-picker-open", %{}, socket(c))
    changed = put_in(c.view, [:public, "clock_ms"], 1)

    {:noreply, updated} =
      GameLive.handle_async({:world_refresh, 1}, {:ok, {changed, nil}}, opened)

    assert updated.assigns.destination_matrix_generation ==
             opened.assigns.destination_matrix_generation

    assert updated.assigns.destination_matrix == nil
    assert calls(c) == 0

    {:noreply, rescheduled} = complete(updated, c)
    assert rescheduled.assigns.destination_matrix == nil
    assert rescheduled.assigns.destination_matrix_cache == nil
    assert rescheduled.assigns.destination_geometry_cache != nil

    assert rescheduled.assigns.destination_matrix_generation >
             opened.assigns.destination_matrix_generation

    assert rescheduled.assigns.destination_matrix_running

    {:noreply, ready} = complete(rescheduled, %{c | view: changed})

    assert ready.assigns.destination_matrix ===
             GameQueries.destination_matrix(c.definitions, changed, c.ship)

    {:noreply, unchanged} =
      GameLive.handle_async({:world_refresh, 1}, {:ok, {changed, nil}}, ready)

    assert unchanged.assigns.destination_matrix === ready.assigns.destination_matrix
    refute unchanged.assigns.destination_matrix_running

    changed_again = put_in(changed, [:public, "clock_ms"], 2)

    {:noreply, refreshing} =
      GameLive.handle_async({:world_refresh, 1}, {:ok, {changed_again, nil}}, ready)

    assert refreshing.assigns.destination_matrix === ready.assigns.destination_matrix
    assert refreshing.assigns.destination_matrix_cache === ready.assigns.destination_matrix_cache
    assert refreshing.assigns.destination_matrix_running

    html =
      render_component(&DestinationPicker.panel/1,
        definitions: c.definitions,
        view: changed_again,
        ship: c.ship,
        matrix: refreshing.assigns.destination_matrix,
        updating: true
      )

    assert html =~ "destination-matrix"
    assert html =~ "destination-picker-updating"
    refute html =~ "destination-picker-loading"

    {:noreply, still_refreshing} = complete(refreshing, %{c | view: changed})
    assert still_refreshing.assigns.destination_matrix === ready.assigns.destination_matrix
    assert still_refreshing.assigns.destination_matrix_running

    {:noreply, replaced} = complete(still_refreshing, %{c | view: changed_again})

    assert replaced.assigns.destination_matrix_cache.key ===
             DestinationMatrixCache.key(c.definitions, changed_again, c.ship)

    assert replaced.assigns.destination_matrix ===
             GameQueries.destination_matrix(c.definitions, changed_again, c.ship)

    refute replaced.assigns.destination_matrix_running
  end

  test "closing, reopening and logout reject late results", c do
    {:noreply, opened} = GameLive.handle_event("destination-picker-open", %{}, socket(c))
    old_generation = opened.assigns.destination_matrix_generation
    result = DestinationMatrixCache.calculate(c.definitions, c.view, c.ship, nil)
    {:noreply, closed} = GameLive.handle_event("destination-picker-close", %{}, opened)
    {:noreply, reopened} = GameLive.handle_event("destination-picker-open", %{}, closed)

    {:noreply, ignored} =
      GameLive.handle_async({:destination_matrix, old_generation}, {:ok, result}, reopened)

    assert ignored === reopened

    {:noreply, logged_out} =
      GameLive.handle_async({:world_refresh, 1}, {:ok, {%{c.view | private: nil}, nil}}, reopened)

    assert logged_out.assigns.destination_matrix_cache == nil
    assert logged_out.assigns.destination_matrix == nil
    refute logged_out.assigns.destination_picker_open
    refute logged_out.assigns.destination_matrix_running

    {:noreply, ignored} =
      GameLive.handle_async(
        {:destination_matrix, reopened.assigns.destination_matrix_generation},
        {:ok, result},
        logged_out
      )

    assert ignored === logged_out
  end

  test "a different ship or changed financial state rejects old estimates", c do
    for changed <- [
          put_in(c.view, [:private, "company", "cash"], 0),
          put_in(c.view, [:private, "ships", c.ship["id"], "cargo"], [
            %{"good" => "lumber", "quantity" => 1, "unit_cost" => 1}
          ])
        ] do
      {:noreply, opened} = GameLive.handle_event("destination-picker-open", %{}, socket(c))

      {:noreply, updated} =
        GameLive.handle_async({:world_refresh, 1}, {:ok, {changed, nil}}, opened)

      {:noreply, pending} = complete(updated, c)
      assert pending.assigns.destination_matrix == nil
      assert pending.assigns.destination_matrix_running
    end

    other = Map.put(c.ship, "id", "other")
    other_view = put_in(c.view, [:private, "ships", "other"], other)
    {:noreply, opened} = GameLive.handle_event("destination-picker-open", %{}, socket(c))
    switched = Phoenix.Component.assign(opened, selected_ship: "other")

    {:noreply, updated} =
      GameLive.handle_async({:world_refresh, 1}, {:ok, {other_view, nil}}, switched)

    {:noreply, pending} = complete(updated, c)
    assert pending.assigns.ship["id"] == "other"
    assert pending.assigns.destination_matrix == nil
  end

  test "a replacement publishes changed ranking together with its new estimates", c do
    {_, catalogue} = TijaraTides.CommandFuzzer.fixture()

    definitions =
      c.definitions
      |> put_in([:catalogue, "ports", "Dubai"], catalogue["ports"]["Dubai"])
      |> put_in([:catalogue, "routes", "Singapore|Dubai"], catalogue["routes"]["Singapore|Dubai"])

    view =
      update_in(c.view, [:markets], fn markets ->
        Map.new(markets, fn {key, quote} ->
          {key,
           if(String.starts_with?(key, ["Colombo|", "Dubai|"]),
             do: %{quote | "demand" => 0},
             else: quote
           )}
        end)
      end)

    buyer = %{view.markets["Colombo|lumber"] | "demand" => 100, "buyer_budget" => 100_000_000}

    view =
      view
      |> put_in([:markets, "Colombo|lumber"], %{buyer | "bid" => 100_000})
      |> put_in([:markets, "Dubai|lumber"], %{buyer | "bid" => 10_000})

    view =
      view
      |> put_in([:private, "company", "cash"], 100_000_000)
      |> put_in([:markets, "Singapore|lumber", "stock"], 100)
      |> put_in([:markets, "Singapore|lumber", "ask"], 1000)

    c = %{c | definitions: definitions, view: view}
    {:noreply, opened} = GameLive.handle_event("destination-picker-open", %{}, socket(c))
    {:noreply, ready} = complete(opened, c)
    assert Enum.map(ready.assigns.destination_matrix.rows, & &1.port) == ["Colombo", "Dubai"]

    changed =
      view
      |> put_in([:markets, "Colombo|lumber", "bid"], 10_000)
      |> put_in([:markets, "Dubai|lumber", "bid"], 100_000)

    {:noreply, pending} = GameLive.handle_async({:world_refresh, 1}, {:ok, {changed, nil}}, ready)
    assert pending.assigns.destination_matrix === ready.assigns.destination_matrix
    {:noreply, replaced} = complete(pending, %{c | view: changed})
    assert Enum.map(replaced.assigns.destination_matrix.rows, & &1.port) == ["Dubai", "Colombo"]

    html =
      render_component(&DestinationPicker.panel/1,
        definitions: definitions,
        view: changed,
        ship: c.ship,
        matrix: replaced.assigns.destination_matrix
      )

    assert LazyHTML.from_fragment(html) |> LazyHTML.query("tbody tr") |> LazyHTML.attribute("id") ==
             ["destination-row-Dubai", "destination-row-Colombo"]
  end

  test "failed refresh keeps completed estimates and retries without clearing them", c do
    {:noreply, opened} = GameLive.handle_event("destination-picker-open", %{}, socket(c))
    {:noreply, ready} = complete(opened, c)
    changed = put_in(c.view, [:private, "company", "cash"], 0)

    {:noreply, refreshing} =
      GameLive.handle_async({:world_refresh, 1}, {:ok, {changed, nil}}, ready)

    assert refreshing.assigns.destination_matrix === ready.assigns.destination_matrix

    {:noreply, failed} =
      GameLive.handle_async(
        {:destination_matrix, refreshing.assigns.destination_matrix_generation},
        {:exit, :failed},
        refreshing
      )

    assert failed.assigns.destination_matrix === ready.assigns.destination_matrix
    assert failed.assigns.destination_matrix_error
    {:noreply, retry} = GameLive.handle_event("destination-picker-open", %{}, failed)
    assert retry.assigns.destination_matrix === ready.assigns.destination_matrix
    assert retry.assigns.destination_matrix_running
    {:noreply, replaced} = complete(retry, %{c | view: changed})

    assert replaced.assigns.destination_matrix ===
             GameQueries.destination_matrix(c.definitions, changed, c.ship)

    assert replaced.assigns.destination_matrix != ready.assigns.destination_matrix
  end

  test "completed estimates never carry over to another owner, hull or departure port", c do
    {:noreply, opened} = GameLive.handle_event("destination-picker-open", %{}, socket(c))
    {:noreply, ready} = complete(opened, c)

    for changed <- [
          put_in(c.view, [:private, "account", "id"], "another-owner"),
          put_in(c.view, [:private, "ships", c.ship["id"], "port"], "Colombo")
        ] do
      {:noreply, updated} =
        GameLive.handle_async({:world_refresh, 1}, {:ok, {changed, nil}}, ready)

      assert updated.assigns.destination_matrix == nil
      assert updated.assigns.destination_matrix_cache == nil
    end

    other = Map.put(c.ship, "id", "other")
    changed = put_in(c.view, [:private, "ships", "other"], other)
    selected = Phoenix.Component.assign(ready, selected_ship: "other")

    {:noreply, updated} =
      GameLive.handle_async({:world_refresh, 1}, {:ok, {changed, nil}}, selected)

    assert updated.assigns.destination_matrix == nil
  end

  test "failure leaves a usable popup and explicit retry starts a new generation", c do
    {:noreply, opened} = GameLive.handle_event("destination-picker-open", %{}, socket(c))

    {:noreply, failed} =
      GameLive.handle_async(
        {:destination_matrix, opened.assigns.destination_matrix_generation},
        {:exit, :failed},
        opened
      )

    assert failed.assigns.destination_matrix_error
    refute failed.assigns.destination_matrix_running

    html =
      render_component(&DestinationPicker.panel/1,
        definitions: c.definitions,
        view: c.view,
        ship: c.ship,
        matrix: nil,
        error: true
      )

    assert html =~ "Could not calculate trade estimates."
    assert html =~ "Try again"
    refute html =~ "Calculating trade estimates..."
    {:noreply, retry} = GameLive.handle_event("destination-picker-open", %{}, failed)
    assert retry.assigns.destination_matrix_running
    refute retry.assigns.destination_matrix_error

    assert retry.assigns.destination_matrix_generation >
             opened.assigns.destination_matrix_generation

    {:noreply, ignored} =
      GameLive.handle_async(
        {:destination_matrix, opened.assigns.destination_matrix_generation},
        {:exit, :failed},
        retry
      )

    assert ignored === retry
  end

  defp calls(c) do
    {:call_count, count} = :erlang.trace_info(c.mfa, :call_count)
    count
  end
end
