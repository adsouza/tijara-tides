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

  test "LiveView close and reopen and supplied-matrix rendering perform no new planning", c do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        destination_matrix_cache: nil,
        definitions: c.definitions,
        view: c.view,
        ship: c.ship
      }
    }

    {:noreply, opened} = GameLive.handle_event("destination-picker-open", %{}, socket)
    assert calls(c) == 1
    {:noreply, closed} = GameLive.handle_event("destination-picker-close", %{}, opened)
    {:noreply, reopened} = GameLive.handle_event("destination-picker-open", %{}, closed)
    assert reopened.assigns.destination_matrix === opened.assigns.destination_matrix

    html =
      render_component(&DestinationPicker.panel/1,
        definitions: c.definitions,
        view: c.view,
        ship: c.ship,
        matrix: reopened.assigns.destination_matrix
      )

    assert html =~ "destination-picker"
    assert calls(c) == 1
  end

  test "LiveView background refresh invalidates an open picker and discards private data on logout",
       c do
    cache = DestinationMatrixCache.refresh(nil, c.definitions, c.view, c.ship, true)

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        destination_matrix_cache: cache,
        destination_matrix: cache.matrix,
        destination_picker_open: true,
        definitions: c.definitions,
        view: c.view,
        ship: c.ship,
        selected_ship: c.ship["id"],
        preferred_locale: nil,
        handling_focus_ship: nil,
        system_notices: [],
        first_ship_port_selected: false,
        trade_context: nil,
        trade_quantities: %{},
        trade_edited: MapSet.new(),
        protection: "none",
        refresh_generation: 1,
        refresh_pending: false,
        dropdown_active: false
      }
    }

    {:noreply, unchanged} =
      GameLive.handle_async({:world_refresh, 1}, {:ok, {c.view, nil}}, socket)

    assert calls(c) == 1
    assert unchanged.assigns.destination_matrix === cache.matrix
    changed = put_in(c.view, [:public, "clock_ms"], 1)

    {:noreply, updated} =
      GameLive.handle_async({:world_refresh, 1}, {:ok, {changed, nil}}, unchanged)

    assert calls(c) == 2

    assert updated.assigns.destination_matrix ==
             GameQueries.destination_matrix(c.definitions, changed, c.ship)

    {:noreply, logged_out} =
      GameLive.handle_async({:world_refresh, 1}, {:ok, {%{changed | private: nil}, nil}}, updated)

    assert logged_out.assigns.destination_matrix_cache == nil
    assert logged_out.assigns.destination_matrix == nil
    refute logged_out.assigns.destination_picker_open
  end

  defp calls(c) do
    {:call_count, count} = :erlang.trace_info(c.mfa, :call_count)
    count
  end
end
