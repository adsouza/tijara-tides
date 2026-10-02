defmodule TijaraTides.Domain.EstimateContractTest do
  # Read-model estimates use the same rules the transitions apply.
  use ExUnit.Case, async: true

  alias TijaraTides.Domain.{Commands, Game, Markets, Ship, State}
  alias TijaraTides.UseCases.GameQueries

  defp world(port, package) do
    cat = TijaraTides.UseCases.Game.definitions().catalogue
    s = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, cat)
    {:ok, s, _} = Game.seed_invite(s, "invite")
    {:ok, s, _} = Game.redeem(s, "invite", "session", %{id: "a", wall_ms: 0})

    {:ok, s, _} =
      TijaraTides.CompanyFixture.create_company(
        s,
        Game.get(s, "accounts", "a"),
        "a",
        port,
        package,
        %{id: "aco", catalogue: cat}
      )

    {s, cat}
  end

  test "displayed purchase handling time includes tank cleaning, as loading does" do
    {s, cat} = world("Abu Dhabi", "oil")

    other =
      cat["goods"]
      |> Enum.find(fn {id, item} -> item["hold"] == "liquid" and id != "crude_oil" end)
      |> elem(0)

    s = State.put(s, "ships", "aco:1", %{Game.get(s, "ships", "aco:1") | "last_liquid" => other})
    ship = Game.get(s, "ships", "aco:1")
    quote = Markets.quotes(s, cat)["Abu Dhabi|crude_oil"]
    item = cat["goods"]["crude_oil"]

    destination =
      cat["routes"]
      |> Map.keys()
      |> Enum.filter(&String.starts_with?(&1, "Abu Dhabi|"))
      |> Enum.map(&String.replace_prefix(&1, "Abu Dhabi|", ""))
      |> Enum.sort()
      |> hd()

    {:ok, bought, _} =
      Commands.execute(
        s,
        Game.get(s, "accounts", "a"),
        %{
          "action" => "buy",
          "ship" => "aco:1",
          "good" => "crude_oil",
          "quantity" => 10,
          "limit" => quote["ask"],
          "destination" => destination
        },
        %{id: "buy", catalogue: cat}
      )

    loading = Game.get(bought, "ships", "aco:1")["arrive_ms"] - s.clock_ms
    assert GameQueries.handling_time(quote, 10, ship, item, "buy") == loading
    assert loading > GameQueries.handling_time(quote, 10, ship, item, "sell")
  end

  test "crew wage estimates match settlement for idle and sailing time" do
    {s, _cat} = world("Jakarta", "general")
    row = Game.get(s, "ships", "aco:1")
    docked = %{Ship.Rows.decode(row) | last_cost_ms: 0, crew_remainder: 0}

    for elapsed <- [120_000, 75_000, 1] do
      {_, effects} = Ship.advance(docked, elapsed, elapsed, false, 600, docked.book_value)
      estimate = Ship.crew_estimate(%{row | "crew_remainder" => 0}, 0, elapsed)
      # Settlement carries the fraction forward; the estimate rounds it up.
      assert estimate == effects.crew + if(rem(elapsed, 120_000) == 0, do: 0, else: 1)
    end

    # Sailing costs twice the idle rate.
    crew = TijaraTides.Domain.ShipClass.all()[row["class"]]["crew"]
    assert Ship.crew_numerator(crew, 60_000, 0, 0) == Ship.crew_numerator(crew, 0, 120_000, 0)
  end
end
