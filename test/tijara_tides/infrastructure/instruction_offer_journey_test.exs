defmodule TijaraTides.Infrastructure.InstructionOfferJourneyTest do
  use ExUnit.Case, async: false
  @moduletag :game_database
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias TijaraTides.Domain.{CompanyFinanceWorld, Game, Markets, Trading}
  alias TijaraTides.Infrastructure.GameServer
  alias TijaraTides.SqlReplay, as: Sql
  @endpoint TijaraTidesWeb.Endpoint

  setup_all do
    Sql.repo()
  end

  test "the unchanged rendered buy default completes both voyages and handling with tight cash" do
    Sql.with_world(fn c ->
      {conn, token} = TijaraTides.WebFormFixture.session(c)

      {:ok, %{"company_id" => company}} =
        TijaraTides.CompanyFixture.command(
          token,
          "formation",
          %{
            "action" => "company",
            "name" => "Default journey",
            "port" => "Singapore",
            "package" => "general"
          },
          c.server
        )

      id = company <> ":1"
      before = :sys.get_state(c.server)
      ship = Game.get(before.game, "ships", id)
      source = Markets.quote(before.game, before.catalogue, "Jakarta", "lumber")
      projected = %{ship | "port" => "Jakarta"}
      fleet = before.game.entities["ships"] |> Map.values()
      item = before.catalogue["goods"]["lumber"]

      # Four lots fit only if the suggestion forgets the inbound voyage. Derive
      # the cash boundary from the execution rules; the witness is the actual
      # default submitted through the UI completing the entire journey.
      onward =
        Trading.purchase_voyage(projected, item, 4, "Singapore", fleet, 0, before.catalogue)

      cash = Trading.purchase_total(source, projected, item, 4) + onward["required"]
      balance = Game.get(before.game, "companies", company)["cash"]

      next =
        CompanyFinanceWorld.post(before.game, company, "test_funds", [
          {"cash_available", cash - balance},
          {"capital", balance - cash}
        ])

      Sql.persist(c, next)

      {:ok, view, _} = conn |> recycle() |> live("/play")
      render_click(view, "ship", %{"id" => id})
      render_click(view, "preview", %{"destination" => "Jakarta"})

      view
      |> form("form[id='visit-onward-#{id}-Jakarta']", %{
        "onward" => "Singapore",
        "auto_depart" => "true"
      })
      |> render_submit()

      render_change(view, "edit-instruction", %{"side" => "buy", "_target" => ["side"]})
      render_change(view, "edit-instruction", %{"good" => "lumber", "_target" => ["good"]})
      selector = "form[id='instruction-form-#{id}']"

      [value] =
        render(view)
        |> LazyHTML.from_fragment()
        |> LazyHTML.query(selector <> " input[name=quantity]")
        |> LazyHTML.attribute("value")

      target = String.to_integer(value)
      assert target > 0 and target < 4
      refute has_element?(view, selector <> " button[disabled]")
      # Preserve every rendered default, including its price and purchase cap.
      view |> form(selector, %{}) |> render_submit()
      [order] = GameServer.snapshot(token, c.server).private["ship_instructions"] |> Map.values()
      assert order["quantity"] == target and order["filled"] == 0
      render_click(view, "sail", %{})
      snapshot = GameServer.snapshot(token, c.server)
      assert snapshot.private["ships"][id]["status"] == "sailing"

      Sql.advance(
        c.server,
        snapshot.private["ships"][id]["arrive_ms"] - snapshot.public["clock_ms"] + 5
      )

      snapshot = GameServer.snapshot(token, c.server)
      assert snapshot.private["ship_instructions"][order["id"]]["filled"] == target
      assert snapshot.private["ship_instructions"][order["id"]]["status"] == "filled"
      assert snapshot.private["ships"][id]["status"] == "loading"
      Sql.assert_rows(c, :sys.get_state(c.server).game)

      Sql.advance(
        c.server,
        snapshot.private["ships"][id]["arrive_ms"] - snapshot.public["clock_ms"] + 5
      )

      snapshot = GameServer.snapshot(token, c.server)
      assert snapshot.private["ships"][id]["status"] == "sailing"
      assert snapshot.private["ships"][id]["destination"] == "Singapore"
      assert snapshot.private["visit_plans"] == %{}
      Sql.assert_rows(c, :sys.get_state(c.server).game)
      GenServer.stop(view.pid, :normal)
      c = Sql.restart(c)

      assert GameServer.snapshot(token, c.server).private["ships"][id] ==
               snapshot.private["ships"][id]

      Sql.assert_rows(c, :sys.get_state(c.server).game)
    end)
  end
end
