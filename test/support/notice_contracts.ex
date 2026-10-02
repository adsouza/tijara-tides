defmodule TijaraTides.NoticeContracts do
  @moduledoc "Current producer codes and binding contracts; legacy rows stay separate."
  use Boundary, deps: [TijaraTides.Domain, TijaraTides.Localization, TijaraTides.CommandFuzzer]
  import ExUnit.Assertions
  alias TijaraTides.Localization
  alias TijaraTides.Localization.Notifications

  def inventory do
    %{
      "account.suspended" => [],
      "account.invitee_suspended" => [],
      "invitation.accepted" => [],
      "invitation.earned" => [],
      "company.formed" => ~w(company),
      "company.bankrupt" => ~w(company),
      "company.dormant" => ~w(company),
      "company.dormancy_warning" => ~w(company deadline),
      "finance.arrears" => ~w(minutes),
      "finance.arrears_cleared" => [],
      "guarantee.funded" => [],
      "guarantee.settled" => ~w(loss refund),
      "ship.loaded" => ~w(ship port),
      "ship.unloaded" => ~w(ship port),
      "ship.departed" => ~w(ship port destination),
      "ship.departure_wait" => ~w(ship destination reason),
      "ship.weather" => ~w(ship destination minutes),
      "funding.timeout" => ~w(ship),
      "instruction.updated" => ~w(ship port side cargo filled quantity reason),
      "route.paused" => ~w(reason),
      "route.wait_expired" => ~w(ship port),
      "linked.unfunded" => ~w(port),
      "linked.cancelled" => ~w(ship port quantity cargo refund filled reason),
      "exchange.cancelled" => ~w(port),
      "auction.closed" => ~w(port),
      "auction.won" => ~w(quantity cargo price port storage warehouse),
      "auction.ship_won" => ~w(ship price port),
      "warehouse.renewal_open" => ~w(port),
      "warehouse.reservation_released" => ~w(port),
      "warehouse.expired" => ~w(port minutes grace_rate liquidation_rate),
      "warehouse.cleared" => ~w(port refund)
    }
  end

  def arguments do
    %{
      "company" => "Fixture company",
      "ship" => "Fixture vessel",
      "port" => "Fixture port",
      "destination" => "Fixture destination",
      "reason" => "Insufficient fuel funding",
      "side" => "buy",
      "cargo" => "lumber",
      "filled" => 2,
      "quantity" => 7,
      "price" => 123_400,
      "loss" => 234_500,
      "refund" => 345_600,
      "minutes" => 90,
      "storage" => "dry",
      "warehouse" => 3,
      "deadline" => 1_700_000_000_000,
      "grace_rate" => 200,
      "liquidation_rate" => 300
    }
  end

  def assert_notice!(notice) do
    code = notice["code"]
    args = notice["arguments"]
    required = Map.fetch!(inventory(), code)

    assert Enum.all?(required, &Map.has_key?(args, &1)),
           "#{code}: required #{inspect(required)}, actual #{inspect(args)}"

    for locale <- ["en", "ar"] do
      Localization.with_locale(locale, fn ->
        rendered = Notifications.render(notice, %{})
        refute rendered == Localization.text("Notification unavailable"), code
        refute rendered =~ "%{", code

        for key <- required do
          value = args[key]

          expected =
            cond do
              key in ~w(price loss refund grace_rate liquidation_rate) ->
                Localization.money(value)

              key == "minutes" and code == "ship.weather" ->
                Localization.number(value, format: "0.0")

              is_number(value) and key != "deadline" ->
                Localization.number(value)

              key == "deadline" ->
                DateTime.from_unix!(value, :millisecond) |> DateTime.to_iso8601()

              key == "storage" ->
                Notifications.storage_name(value)

              true ->
                Localization.text(value)
            end

          assert rendered =~ expected, "#{code}/#{locale}/#{key} missing #{expected}: #{rendered}"
        end
      end)
    end

    notice
  end

  def expired_fixture do
    {game, catalogue} = TijaraTides.CommandFuzzer.fixture()
    catalogue = Map.put(catalogue, "auctions", %{"interval_ms" => 10_000, "window_ms" => 10_000})

    {:ok, game, _} =
      TijaraTides.CommandFuzzer.execute(
        game,
        catalogue,
        %{
          "action" => "warehouse_lease",
          "port" => "Jakarta",
          "storage" => "dry",
          "blocks" => 1,
          "days" => 1,
          "price" => 100
        },
        "notice-warehouse"
      )

    # A normal lease expiry; retain cargo by purchasing and storing through commands.
    {:ok, game, _} =
      TijaraTides.CommandFuzzer.execute(
        game,
        catalogue,
        %{
          "action" => "buy",
          "ship" => "company:1",
          "good" => "lumber",
          "quantity" => 1,
          "limit" => 1_000_000,
          "destination" => "Singapore"
        },
        "notice-buy"
      )

    game = TijaraTides.Domain.Game.advance(game, 60_000, catalogue)

    {:ok, game, _} =
      TijaraTides.CommandFuzzer.execute(
        game,
        catalogue,
        %{
          "action" => "warehouse_transfer",
          "ship" => "company:1",
          "warehouse" => "notice-warehouse",
          "side" => "store",
          "good" => "lumber",
          "quantity" => 1
        },
        "notice-store"
      )

    game = TijaraTides.Domain.Game.advance(game, 86_400_000 - game.clock_ms, catalogue)
    notice = game.entities["notices"]["warehouse:notice-warehouse"]
    {game, catalogue, notice}
  end

  def funding_fixture do
    {game, catalogue} = TijaraTides.CommandFuzzer.fixture()

    catalogue =
      Map.put(catalogue, "departure_funding", %{
        "wait_ms" => 100,
        "window_ms" => 50,
        "cooldown_ms" => 200
      })

    game =
      Enum.reduce(
        [
          {"origin", %{"operation" => "add_stop", "port" => "Jakarta"}},
          {"destination", %{"operation" => "add_stop", "port" => "Singapore"}},
          {"start", %{"operation" => "start", "auto_depart" => true}}
        ],
        game,
        fn {id, params}, current ->
          {:ok, next, _} =
            TijaraTides.CommandFuzzer.execute(
              current,
              catalogue,
              Map.merge(params, %{"action" => "route", "ship" => "company:1"}),
              id
            )

          next
        end
      )

    {:ok, game, _} =
      TijaraTides.CommandFuzzer.execute(game, catalogue, %{
        "action" => "visit_budget",
        "ship" => "company:1",
        "stop" => "destination",
        "amount" => 100_000
      })

    company = game.entities["companies"]["company"]
    # An explicit balanced fixture withdrawal; it is not counted as a fuzz command.
    available = company["cash"] - company["reserved"]

    game =
      TijaraTides.Domain.CompanyFinanceWorld.post(game, "company", "fixture_funds", [
        {"cash_available", 100 - available},
        {"capital", available - 100}
      ])

    game = TijaraTides.Domain.Game.advance(game, 0, catalogue)
    {game, catalogue}
  end
end
