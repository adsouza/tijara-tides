defmodule TijaraTides.UseCases.CommandPayloadTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias TijaraTides.CommandFuzzer, as: Fuzzer
  alias TijaraTides.CommandFuzzer.Inventory
  alias TijaraTides.UseCases.CommandPayload

  test "schemas cover every dispatch action and route operation" do
    assert CommandPayload.actions() == Inventory.commands()
    assert CommandPayload.route_operations() == Inventory.route_operations()
  end

  test "unknown fields reject for every action before receipt lookup or planning" do
    {game, catalogue} = Fuzzer.fixture(false)
    commands = for action <- Inventory.commands(), action != "route", do: %{"action" => action}

    routes =
      for operation <- Inventory.route_operations(),
          do: %{"action" => "route", "ship" => "company:1", "operation" => operation}

    for payload <- commands ++ routes,
        key <- ["unexpected", "request_id", :name],
        value <- [nil, false, "value"] do
      assert {:error, :unknown_command_fields} =
               Fuzzer.run(game, catalogue, Map.put(payload, key, value),
                 receipt: fn _, _, _ -> flunk("invalid fields reached receipt lookup") end,
                 commit: fn _, _, _ -> flunk("invalid fields committed") end
               )
    end
  end

  test "fields valid for another action or route operation are still unknown" do
    for payload <- [
          %{"action" => "company", "name" => "Safe", "port" => "Jakarta"},
          %{"action" => "invite", "amount" => 1},
          %{"action" => "exchange_cancel", "order" => "order", "price" => 100},
          %{"action" => "route", "operation" => "pause", "ship" => "ship", "port" => nil},
          %{"action" => "route", "operation" => "add_rule", "rule" => "existing"},
          %{"action" => "route", "operation" => "remove_rule", "stop" => "stop"}
        ] do
      assert {:error, :unknown_command_fields} = CommandPayload.validate(payload)
    end
  end

  test "complete instruction, exchange and route terms fit admission together" do
    for payload <- [
          %{
            "action" => "instruction",
            "ship" => "ship",
            "port" => "Jakarta",
            "side" => "buy",
            "good" => "grain",
            "quantity" => 1,
            "limit" => 100,
            "budget" => 1000,
            "onward" => "Singapore",
            "expires_in_ms" => nil,
            "min_remaining_ms" => 0,
            "preset" => "",
            "markdowns" => %{},
            "price_floor" => 0
          },
          %{
            "action" => "exchange_place",
            "warehouse" => "warehouse",
            "good" => "grain",
            "side" => "sell",
            "quantity" => 1,
            "price" => 100,
            "expires_ms" => nil,
            "min_grade" => 0,
            "min_remaining_ms" => 0,
            "markdowns" => %{},
            "price_floor" => 0,
            "preset" => "",
            "rebase" => false
          },
          %{
            "action" => "route",
            "ship" => "ship",
            "operation" => "update_rule",
            "stop" => "stop",
            "rule" => "rule",
            "side" => "buy",
            "good" => "grain",
            "quantity" => 1,
            "limit" => 100,
            "quantity_mode" => "fixed",
            "budget" => 1000,
            "linked_warehouse_id" => "",
            "min_remaining_ms" => 0
          }
        ] do
      assert :ok = CommandPayload.validate(payload)
    end
  end

  test "unsupported actions and operations remain ordinary rejections" do
    for payload <- [
          %{},
          %{"action" => nil},
          %{"action" => "unknown"},
          %{"action" => "route"},
          %{"action" => "route", "operation" => "unknown"}
        ] do
      assert {:error, :unsupported_command} = CommandPayload.validate(payload)
    end
  end

  property "generated unknown keys reject and removing them admits a corrected request" do
    check all(
            suffix <- string(:alphanumeric, max_length: 30),
            value <- member_of([nil, false, 0, ""]),
            max_runs: 50,
            max_shrinking_steps: 100
          ) do
      {game, catalogue} = Fuzzer.fixture(false)
      valid = %{"action" => "company", "name" => "Safe"}

      assert {:error, :unknown_command_fields} =
               Fuzzer.run(game, catalogue, Map.put(valid, "unknown_" <> suffix, value))

      assert {:ok, result} = Fuzzer.run(game, catalogue, valid)
      assert result.reply == %{"company_id" => "allocated"}
    end
  end

  test "company names at the storage cap allow default hull names" do
    alias TijaraTides.Domain.{CompanyFinanceWorld, ReadState}
    {game, catalogue} = Fuzzer.fixture(false)
    name = String.duplicate("e\u0301\u0323", 40)
    assert length(String.codepoints(name)) == 120

    assert {:error, :invalid_name} =
             Fuzzer.run(game, catalogue, %{"action" => "company", "name" => name <> "a"})

    assert {:ok, result} = Fuzzer.run(game, catalogue, %{"action" => "company", "name" => name})

    game =
      CompanyFinanceWorld.post(result.game, result.reply["company_id"], "test_capital", [
        {"cash_available", 20_000_000},
        {"capital", -20_000_000}
      ])

    payload = %{
      "action" => "purchase_ship",
      "class" => "freighter",
      "port" => "Jakarta",
      "price_limit" => 1_000_000_000
    }

    assert {:ok, result} =
             Fuzzer.run(game, catalogue, payload, id: "hull-1", request: "purchase-1")

    assert ReadState.get(result.game, "ships", "hull-1")["name"] == name <> " 1"

    assert {:ok, next} =
             Fuzzer.run(result.game, catalogue, payload, id: "hull-2", request: "purchase-2")

    assert ReadState.get(next.game, "ships", "hull-2")["name"] == name <> " 2"
  end
end
