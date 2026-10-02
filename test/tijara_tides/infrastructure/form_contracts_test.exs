defmodule TijaraTides.Infrastructure.FormContractsTest do
  use ExUnit.Case, async: false
  use ExUnitProperties
  @moduletag :game_database
  import Phoenix.LiveViewTest
  alias TijaraTides.SqlReplay, as: Sql
  alias TijaraTides.Infrastructure.{GameServer, Persistence.Repo}
  alias TijaraTides.CommandFuzzer.Contracts

  setup_all do
    Sql.repo()
  end

  for variant <- [
        :instruction_buy,
        :instruction_sell,
        :exchange_place_buy,
        :exchange_place_sell,
        :exchange_amend_buy,
        :exchange_amend_sell,
        :route_add_buy,
        :route_add_sell,
        :route_update_buy,
        :route_update_sell,
        :borrow,
        :recast
      ] do
    test "valid #{variant} form commits its intended terms and exact replay" do
      Sql.with_world(fn c ->
        f = fixture(c)
        {event, params, assertion} = variant(f, unquote(variant))
        before = :sys.get_state(c.server).game
        submit!(f.view, event, metadata(params))
        after_state = :sys.get_state(c.server).game
        assert after_state.revision == before.revision + 1
        assertion.(after_state)
        submit!(f.view, event, params)
        assert :sys.get_state(c.server).game.revision == after_state.revision
        Sql.assert_rows(c, after_state)
        GenServer.stop(f.view.pid, :normal)
      end)
    end
  end

  for variant <- [:instruction_buy, :exchange_place_buy] do
    property "#{variant} normalization preserves receipt identity and independently expected terms" do
      check all(
              zeros <- integer(0..3),
              markers <-
                uniq_list_of(member_of(~w(quantity price limit minutes expiry_minutes budget)),
                  max_length: 6
                ),
              max_runs: 5,
              max_shrinking_steps: 20
            ) do
        Sql.with_world(fn c ->
          f = fixture(c)
          {event, params, assertion} = variant(f, unquote(variant))
          submit!(f.view, event, params)
          game = :sys.get_state(c.server).game
          assertion.(game)

          equivalent =
            Map.new(params, fn {key, value} ->
              if key in ~w(quantity price limit minutes expiry_minutes budget) and
                   is_binary(value) and value != "",
                 do: {key, String.duplicate("0", zeros) <> value},
                 else: {key, value}
            end)

          equivalent = Enum.reduce(markers, equivalent, &Map.put(&2, "_unused_" <> &1, ""))
          submit!(f.view, event, equivalent)
          assert :sys.get_state(c.server).game.revision == game.revision
          Sql.assert_rows(c, game)
          GenServer.stop(f.view.pid, :normal)
        end)
      end
    end
  end

  test "unsafe Unicode names reject before rows, receipts and ledger; corrected requests still commit" do
    Sql.with_world(fn c ->
      {:ok, %{"session" => token}} = GameServer.redeem(c.code, c.server)
      game = :sys.get_state(c.server).game

      for name <- ["a\0b", "a\nb", "a\u200Db"] do
        assert {:error, :invalid_name} =
                 GameServer.command(
                   token,
                   "unsafe-company",
                   Contracts.name_command(:company, name),
                   c.server
                 )

        assert :sys.get_state(c.server).game == game
        assert GameServer.readiness(c.server) == :ready
      end

      Sql.command(
        c,
        token,
        "safe-company",
        Contracts.name_command(:company, String.duplicate("e\u0301", 60))
      )

      assert [[120]] =
               Repo.query!("SELECT length(name) FROM game_companies WHERE world_id=$1", [c.world]).rows

      for {name, accepted?} <- [
            {String.duplicate("e\u0301", 40), true},
            {String.duplicate("e\u0301", 41), false},
            {"a\0b", false}
          ] do
        before = :sys.get_state(c.server).game
        payload = Contracts.name_command(:preset, name)

        if accepted? do
          Sql.command(c, token, "safe-preset", payload)

          assert [[80]] =
                   Repo.query!(
                     "SELECT length(name) FROM game_markdown_presets WHERE world_id=$1",
                     [c.world]
                   ).rows
        else
          assert {:error, :exchange_freshness_invalid} =
                   GameServer.command(token, "bad-preset", payload, c.server)

          assert :sys.get_state(c.server).game == before
        end
      end

      assert [[2]] =
               Repo.query!("SELECT count(*) FROM game_receipts WHERE world_id=$1", [
                 c.world
               ]).rows

      Sql.assert_rows(c, :sys.get_state(c.server).game)
    end)
  end

  test "a failing replay terminates its owner before a fresh attempt" do
    marker = make_ref()

    assert_raise ExUnit.AssertionError, fn ->
      Sql.with_world(fn c ->
        send(self(), {marker, c.server, c.world})
        flunk("intentional replay failure")
      end)
    end

    assert_received {^marker, pid, world}
    refute Process.alive?(pid)

    Sql.with_world(fn c ->
      refute c.world == world
      assert :sys.get_state(c.server).game.entities["companies"] in [nil, %{}]
    end)
  end

  defp submit!(view, event, params) do
    html = render_submit(view, event, params)
    refute has_element?(view, "#flash-error"), "A valid or equivalent submission was rejected"
    html
  end

  defp fixture(c), do: TijaraTides.WebFormFixture.fixture(c)

  defp variant(_f, :borrow) do
    {"borrow", %{"request_id" => "form-borrow", "amount" => "100"},
     fn game ->
       assert [10_000] == Enum.map(Map.values(game.entities["loans"]), & &1["principal"])
     end}
  end

  defp variant(f, :recast) do
    reply = Sql.command(f.c, f.token, "loan", %{"action" => "borrow", "amount" => 10_000})
    loan = reply["loan_id"]

    {"recast", %{"request_id" => "form-recast", "loan" => loan, "amount" => "10"},
     fn game -> assert game.entities["loans"][loan]["remaining"] == 9_000 end}
  end

  defp variant(f, variant) when variant in [:instruction_buy, :instruction_sell] do
    render_click(f.view, "preview", %{"destination" => "Singapore"})
    side = if variant == :instruction_buy, do: "buy", else: "sell"

    params = %{
      "request_id" => "form-instruction",
      "side" => side,
      "good" => "lumber",
      "quantity" => "1",
      "limit" => "10000",
      "onward" => "Jakarta",
      "expiry_minutes" => "2"
    }

    params =
      if side == "buy",
        do: Map.merge(params, %{"budget" => "10000", "freshness_minutes" => "75"}),
        else: Map.put(params, "preset", "")

    {"add-instruction", params,
     fn game ->
       [order] = Map.values(game.entities["ship_instructions"])

       assert {order["side"], order["quantity"], order["limit"], order["expires_ms"]} ==
                {side, 1, 1_000_000, game.clock_ms + 120_000}

       if side == "buy",
         do: assert(order["budget"] == 1_000_000 and order["min_remaining_ms"] == 4_500_000)
     end}
  end

  defp variant(f, variant)
       when variant in [
              :exchange_place_buy,
              :exchange_place_sell,
              :exchange_amend_buy,
              :exchange_amend_sell
            ] do
    side = if variant in [:exchange_place_buy, :exchange_amend_buy], do: "buy", else: "sell"
    amend? = variant in [:exchange_amend_buy, :exchange_amend_sell]

    params = %{
      "request_id" => "form-exchange",
      "action" => "exchange_place",
      "warehouse" => f.warehouse,
      "good" => "lumber",
      "side" => side,
      "quantity" => "2",
      "price" => if(side == "buy", do: "1", else: "10000"),
      "minutes" => "2"
    }

    params =
      if amend? do
        _reply =
          Sql.command(f.c, f.token, "initial-order", %{
            "action" => "exchange_place",
            "warehouse" => f.warehouse,
            "good" => "lumber",
            "side" => side,
            "quantity" => 1,
            "price" => if(side == "buy", do: 100, else: 1_000_000)
          })

        params
        |> Map.put("action", "exchange_amend")
        |> Map.put(
          "order",
          GameServer.snapshot(f.token, f.c.server).private["exchange_orders"]
          |> Map.keys()
          |> hd()
        )
        |> Map.drop(~w(warehouse good side))
      else
        params
      end

    {"exchange", params,
     fn game ->
       [order] = Map.values(game.entities["exchange_orders"])

       assert {order["side"], order["quantity"], order["price"], order["expires_ms"]} ==
                {side, 2, if(side == "buy", do: 100, else: 1_000_000), game.clock_ms + 120_000}
     end}
  end

  defp variant(f, variant) do
    side = if variant in [:route_add_buy, :route_update_buy], do: "buy", else: "sell"

    _reply =
      Sql.command(f.c, f.token, "stop", %{
        "action" => "route",
        "ship" => f.ship,
        "operation" => "add_stop",
        "port" => "Jakarta"
      })

    stop = GameServer.snapshot(f.token, f.c.server).private["route_stops"] |> Map.keys() |> hd()

    params = %{
      "request_id" => "form-route",
      "operation" => "add_rule",
      "stop" => stop,
      "side" => side,
      "good" => "lumber",
      "quantity_mode" => "fixed",
      "quantity" => "2",
      "limit" => "10000",
      "freshness_minutes" => "0"
    }

    params = if side == "buy", do: Map.put(params, "budget", "10000"), else: params

    params =
      if variant in [:route_update_buy, :route_update_sell] do
        _reply =
          Sql.command(f.c, f.token, "rule", %{
            "action" => "route",
            "ship" => f.ship,
            "operation" => "add_rule",
            "stop" => stop,
            "side" => side,
            "good" => "lumber",
            "quantity" => 1,
            "limit" => 1_000_000
          })

        params
        |> Map.put("operation", "update_rule")
        |> Map.put(
          "rule",
          GameServer.snapshot(f.token, f.c.server).private["route_rules"] |> Map.keys() |> hd()
        )
      else
        params
      end

    {"route", params,
     fn game ->
       [rule] = Map.values(game.entities["route_rules"])
       assert {rule["side"], rule["quantity"], rule["limit"]} == {side, 2, 1_000_000}
       if side == "buy", do: assert(rule["budget"] == 1_000_000)
     end}
  end

  defp metadata(params),
    do:
      Map.merge(params, Map.new(params, fn {k, _} -> {"_unused_" <> k, ""} end))
      |> Map.put("_target", ["side"])
end
