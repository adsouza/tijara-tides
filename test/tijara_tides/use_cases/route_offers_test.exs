defmodule TijaraTides.UseCases.RouteOffersTest do
  # The add-stop form offers exactly the ports the command accepts, and hides itself
  # while next-port instructions block a route, which the command also refuses.
  use ExUnit.Case, async: true

  alias TijaraTides.Domain.{Game, ShipWorld, Visibility}
  alias TijaraTides.UseCases.GameQueries

  setup do
    cat = TijaraTides.UseCases.Game.definitions().catalogue
    s = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, cat)
    {:ok, s, _} = Game.seed_invite(s, "invite")
    {:ok, s, _} = Game.redeem(s, "invite", "session", %{id: "a", wall_ms: 0})

    {:ok, s, _} =
      TijaraTides.CompanyFixture.create_company(
        s,
        Game.get(s, "accounts", "a"),
        "a",
        "Jakarta",
        "general",
        %{id: "aco", catalogue: cat}
      )

    %{s: s, cat: cat}
  end

  defp editor(c, s) do
    private = Visibility.private(s, Game.get(s, "accounts", "a"))
    GameQueries.route_editor(private, private["ships"]["aco:1"], c.cat)
  end

  defp route(c, s, params, id),
    do:
      ShipWorld.edit_route(
        s,
        Game.get(s, "accounts", "a"),
        Map.merge(%{"ship" => "aco:1"}, params),
        %{id: id, catalogue: c.cat}
      )

  defp add_stop(c, s, port, id \\ "stop"),
    do: route(c, s, %{"operation" => "add_stop", "port" => port}, id <> "-" <> port)

  defp accepts_exactly_offered(c, s) do
    offered = editor(c, s).stop_ports
    assert offered != []
    for port <- offered, do: assert({:ok, _, _} = add_stop(c, s, port))

    for port <- Map.keys(c.cat["ports"]) -- offered,
        do: assert({:error, :route_port_invalid} = add_stop(c, s, port))

    offered
  end

  test "a draft route offers every port except the last stop's", c do
    {:ok, s, _} = add_stop(c, c.s, "Jakarta")
    offered = accepts_exactly_offered(c, s)
    refute "Jakarta" in offered
    assert length(offered) == map_size(c.cat["ports"]) - 1
  end

  test "a started route also withholds the first stop, the new last leg's return", c do
    {:ok, s, _} = add_stop(c, c.s, "Jakarta")
    {:ok, s, _} = add_stop(c, s, "Singapore")
    {:ok, s, _} = route(c, s, %{"operation" => "start", "auto_depart" => true}, "start")
    offered = accepts_exactly_offered(c, s)
    refute "Jakarta" in offered
    refute "Singapore" in offered
  end

  test "next-port instructions hide the add-stop form exactly when the command refuses", c do
    refute editor(c, c.s).instructions_block
    assert {:ok, _, _} = add_stop(c, c.s, "Singapore")

    {:ok, s, _} =
      TijaraTides.UseCases.GameCommands.execute(
        c.s,
        Game.get(c.s, "accounts", "a"),
        %{
          "action" => "instruction",
          "ship" => "aco:1",
          "port" => "Singapore",
          "side" => "buy",
          "good" => "lumber",
          "quantity" => 1,
          "limit" => 1_000_000,
          "budget" => 1_000_000,
          "onward" => "Jakarta"
        },
        %{id: "instruction", wall_ms: 0, catalogue: c.cat, auction_seed: "seed"}
      )

    assert editor(c, s).instructions_block
    assert {:error, :route_existing_instructions} = add_stop(c, s, "Singapore")
  end
end
