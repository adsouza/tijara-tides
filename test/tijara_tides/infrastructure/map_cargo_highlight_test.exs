defmodule TijaraTides.Infrastructure.MapCargoHighlightTest do
  use ExUnit.Case, async: false
  @moduletag :game_database
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias TijaraTides.Domain.State
  alias TijaraTides.SqlReplay, as: Sql
  alias TijaraTides.UseCases.Game
  alias TijaraTidesWeb.WorldMap
  @endpoint TijaraTidesWeb.Endpoint

  setup_all do
    Sql.repo()
  end

  defp attribute(view, selector, name) do
    render(view)
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> LazyHTML.attribute(name)
  end

  defp pressed(view), do: attribute(view, "[data-map-cargo][aria-pressed=true]", "data-map-cargo")

  defp highlighted(view),
    do: view |> attribute("#world-map g[data-cargo-highlight]", "phx-value-id") |> MapSet.new()

  # A marker that groups several ports turns red when any of them is listed.
  defp markers_for(view, side) do
    ports = view |> attribute("#cargo-#{side} tbody tr[data-port]", "data-port") |> MapSet.new()

    for marker <- WorldMap.markers(Game.definitions().catalogue, nil),
        Enum.any?(marker.ports, &MapSet.member?(ports, &1)),
        into: MapSet.new(),
        do: marker.name
  end

  test "cargo emoji beside the map mark the ports listed in the supply or demand table" do
    Sql.with_world(fn c ->
      {conn, token} = TijaraTides.WebFormFixture.session(c)

      {:ok, _} =
        TijaraTides.CompanyFixture.command(
          token,
          "formation",
          %{
            "action" => "company",
            "name" => "Cargo map",
            "port" => "Singapore",
            "package" => "general"
          },
          c.server
        )

      # Sold-out grain keeps its demand, so only its supply side has no ports.
      before = :sys.get_state(c.server).game

      next =
        for {id, market} <- before.entities["markets"],
            String.ends_with?(id, "|grain"),
            reduce: before,
            do: (acc -> State.put(acc, "markets", id, %{market | "stock" => 0}))

      Sql.persist(c, next)

      {:ok, view, _} = conn |> recycle() |> live("/play")
      assert pressed(view) == []
      assert highlighted(view) == MapSet.new()

      # Both strips offer the same cargo, in the same order, as the dropdown.
      offered = attribute(view, "[data-map-cargo=supply]", "phx-value-good")
      assert offered == attribute(view, "[data-map-cargo=demand]", "phx-value-good")
      assert length(offered) > 1

      view |> element("[data-map-cargo=supply][phx-value-good=lumber]") |> render_click()
      assert pressed(view) == ["supply"]

      assert attribute(view, "[data-map-cargo][aria-pressed=true]", "phx-value-good") == [
               "lumber"
             ]

      assert has_element?(view, "#market-good", "Lumber")
      supply = markers_for(view, "supply")
      assert MapSet.size(supply) > 0
      assert highlighted(view) == supply

      # Only one emoji is active across both strips.
      view |> element("[data-map-cargo=demand][phx-value-good=lumber]") |> render_click()
      assert pressed(view) == ["demand"]
      demand = markers_for(view, "demand")
      assert MapSet.size(demand) > 0
      assert highlighted(view) == demand
      refute demand == supply

      # The highlight follows the dropdown's cargo on the same side.
      [other | _] = offered -- ["lumber"]
      render_click(view, "market-good", %{"good" => other})
      assert attribute(view, "[data-map-cargo][aria-pressed=true]", "phx-value-good") == [other]
      assert highlighted(view) == markers_for(view, "demand")

      # Clicking the active emoji again turns it off and keeps the cargo.
      view |> element("[data-map-cargo=demand][phx-value-good=#{other}]") |> render_click()
      assert pressed(view) == []
      assert highlighted(view) == MapSet.new()

      assert attribute(view, "[data-map-cargo=supply][phx-value-good=#{other}]", "aria-pressed") ==
               ["false"]

      # An emoji is offered exactly when its table lists a port.
      for good <- offered, side <- ["supply", "demand"] do
        render_click(view, "market-good", %{"good" => good})
        disabled = attribute(view, "[data-map-cargo=#{side}][phx-value-good=#{good}]", "disabled")
        assert disabled == [] == MapSet.size(markers_for(view, side)) > 0, "#{side} #{good}"
      end

      assert attribute(view, "[data-map-cargo=supply][phx-value-good=grain]", "disabled") != []
      assert attribute(view, "[data-map-cargo=demand][phx-value-good=grain]", "disabled") == []
      render_click(view, "map-cargo", %{"side" => "supply", "good" => "grain"})
      assert pressed(view) == ["supply"]
      assert highlighted(view) == MapSet.new()

      render_click(view, "map-cargo", %{"side" => "supply", "good" => "lumber"})

      for params <- [
            %{"side" => "both", "good" => "lumber"},
            %{"side" => "demand", "good" => "unobtainium"},
            %{"side" => "demand"}
          ] do
        render_click(view, "map-cargo", params)
        assert pressed(view) == ["supply"]
        assert highlighted(view) == markers_for(view, "supply")
      end
    end)
  end
end
