defmodule TijaraTides.Domain.HandlingTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{CargoRules, Ship, CargoFreshness, Fleet}
  alias Ship.CargoBatch

  test "port speed and cargo factors use exact upward rounding and a minimum duration" do
    c = TijaraTides.Infrastructure.GameCatalogue.all()
    assert CargoRules.handling_ms(100, "Jakarta", "lumber", c) == 50_000
    assert CargoRules.handling_ms(100, "Singapore", "lumber", c) == 25_000
    assert CargoRules.handling_ms(100, "Jakarta", "fruit", c) == 62_500
    assert CargoRules.handling_ms(100, "Jakarta", "iron_ore", c) == 50_000
    assert CargoRules.handling_ms(100, "Jakarta", "copper_scrap", c) == 75_000
    assert CargoRules.handling_ms(100, "Jakarta", "crude_oil", c) == 37_500
    assert CargoRules.handling_ms(5, "Singapore", "fruit", c) == 1563
    assert CargoRules.handling_ms(1, "Singapore", "crude_oil", c) == 1000
    tuned = put_in(c, ["handling", "speed_ms_per_lot", "slow"], 1000)
    assert CargoRules.handling_ms(100, "Jakarta", "fruit", tuned) == 125_000
  end

  test "committed handling, purchase funding and freshness previews agree at both ports" do
    c = TijaraTides.Infrastructure.GameCatalogue.all()

    s =
      TijaraTides.Domain.Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, c)

    {:ok, s, _} = TijaraTides.Domain.Game.seed_invite(s, "invite")
    {:ok, s, _} = TijaraTides.Domain.Game.redeem(s, "invite", "session", %{id: "a", wall_ms: 0})

    {:ok, s, _} =
      TijaraTides.CompanyFixture.create_company(
        s,
        TijaraTides.Domain.State.get(s, "accounts", "a"),
        "Trader",
        "Jakarta",
        "general",
        %{id: "co", catalogue: c}
      )

    a = TijaraTides.Domain.State.get(s, "accounts", "a")
    row = TijaraTides.Domain.State.owned(s, "ships", "company_id", a["company_id"]) |> hd()
    ship = Ship.Rows.decode(row)

    batch =
      CargoFreshness.initialize(
        %CargoBatch{
          good: "fruit",
          quantity: 20,
          lot_id: "fruit",
          expires_ms: 100_000,
          unit_cost: 1
        },
        0,
        c["goods"]["fruit"]
      )

    loaded = Ship.record_purchase(ship, [batch], 0, 0, c)
    assert loaded.arrive_ms == 12_500
    assert Ship.Rows.decode(Ship.Rows.encode(loaded)) == loaded

    quote =
      TijaraTides.Domain.Services.TradeSettlement.purchase_voyage(
        row,
        c["goods"]["fruit"],
        20,
        "Singapore",
        [row],
        0,
        c
      )

    assert quote["loading_ms"] == loaded.arrive_ms
    market = TijaraTides.Domain.PortCargoMarketWorld.quote(s, c, "Jakarta", "fruit")

    preview =
      TijaraTides.UseCases.MarketQueries.trade_freshness(market, row, "buy", "fruit", 20, 0)

    assert preview["handling_ms"] == loaded.arrive_ms
    [arrival] = CargoRules.voyage_freshness(Ship.Rows.encode(loaded), 0, 1000, "Singapore", c)
    assert arrival["arrival_ms"] - arrival["unloaded_ms"] == 6250
    dry = %{loaded | status: "docked", port: "Singapore"}

    {_, unloaded, _} =
      Ship.record_sale(%TijaraTides.Domain.CargoLots.Scope{clock_ms: 0}, dry, "fruit", 20, nil, c)

    assert unloaded.arrive_ms == 6250
    assert Fleet.classes()[dry.class]
  end
end
