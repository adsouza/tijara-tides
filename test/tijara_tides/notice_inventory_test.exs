defmodule TijaraTides.NoticeInventoryTest do
  use ExUnit.Case, async: true
  alias TijaraTides.CommandFuzzer.Inventory
  alias TijaraTides.NoticeContracts

  test "current producer inventory resolves imported qualified conditional and effect codes" do
    producers = Inventory.notices()
    codes = producers |> Enum.map(&elem(&1, 0)) |> MapSet.new()
    assert codes == NoticeContracts.inventory() |> Map.keys() |> MapSet.new(), inspect(producers)

    for {code, required} <- NoticeContracts.inventory() do
      notice = %{"code" => code, "arguments" => Map.take(NoticeContracts.arguments(), required)}
      NoticeContracts.assert_notice!(notice)
    end
  end

  test "unregistered and unresolved dynamic producers cannot silently disappear" do
    literal =
      "defmodule Probe do; def f(s), do: Notices.notice(s, \"owner\", \"id\", {\"new.notice\", %{}}); end"

    assert [{"new.notice", "probe.ex", _}] = Inventory.notice_source(literal, "probe.ex")
    refute Map.has_key?(NoticeContracts.inventory(), "new.notice")
    dynamic = String.replace(literal, "\"new.notice\"", "unknown()")

    assert_raise ArgumentError, ~r/Unresolved notice producer probe.ex/, fn ->
      Inventory.notice_source(dynamic, "probe.ex")
    end

    effect = String.replace(literal, "Notices.notice", "notice")
    assert [{"new.notice", _, _}] = Inventory.notice_source(effect, "probe.ex")

    assert [{"new.effect", _, _}] =
             Inventory.notice_source(
               "%{\"code\" => \"new.effect\", \"arguments\" => %{}}",
               "probe.ex"
             )

    assert_raise ArgumentError, ~r/Unresolved notice effect/, fn ->
      Inventory.notice_source("%{\"code\" => unknown(), \"arguments\" => %{}}", "probe.ex")
    end
  end

  test "actual lease expiry carries both rates and grace through the renderer, then clears once" do
    {game, catalogue, notice} = NoticeContracts.expired_fixture()
    assert notice["code"] == "warehouse.expired"

    assert notice["arguments"] == %{
             "port" => "Jakarta",
             "minutes" => 720,
             "grace_rate" => 100,
             "liquidation_rate" => 125
           }

    NoticeContracts.assert_notice!(notice)
    liquidating = TijaraTides.Domain.Game.advance(game, 43_200_000, catalogue)
    cleared = TijaraTides.Domain.Game.advance(liquidating, 20_000, catalogue)
    notice = cleared.entities["notices"]["warehouse:notice-warehouse"]
    assert notice["code"] == "warehouse.cleared"
    NoticeContracts.assert_notice!(notice)
    repeated = TijaraTides.Domain.Game.advance(cleared, 0, catalogue)
    assert repeated.entities["notices"]["warehouse:notice-warehouse"] == notice
  end

  test "domain funding wait timeout and resumed departure retain their rendered reasons" do
    {waiting, catalogue} = NoticeContracts.funding_fixture()
    notices = Map.values(waiting.entities["notices"])
    wait = Enum.find(notices, &(&1["code"] == "ship.departure_wait"))
    assert wait["arguments"]["reason"] == "Waiting for fuel and the configured purchase budget"
    NoticeContracts.assert_notice!(wait)
    accumulating = TijaraTides.Domain.Game.advance(waiting, 100, catalogue)
    deadline = accumulating.entities["departure_requests"]["company:1"]["window_deadline_ms"]
    assert deadline == 150
    timed_out = TijaraTides.Domain.Game.advance(accumulating, 50, catalogue)

    timeout =
      Enum.find(Map.values(timed_out.entities["notices"]), &(&1["code"] == "funding.timeout"))

    NoticeContracts.assert_notice!(timeout)

    funded =
      TijaraTides.Domain.CompanyFinanceWorld.post(waiting, "company", "fixture_funds", [
        {"cash_available", 1_000_000},
        {"capital", -1_000_000}
      ])

    resumed = TijaraTides.Domain.Game.advance(funded, 0, catalogue)
    assert resumed.entities["ships"]["company:1"]["status"] == "sailing"

    departed =
      Enum.find(Map.values(resumed.entities["notices"]), &(&1["code"] == "ship.departed"))

    NoticeContracts.assert_notice!(departed)
  end
end
