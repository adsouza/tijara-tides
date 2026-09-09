defmodule TijaraTides.Infrastructure.GamePersistenceTest do
  use ExUnit.Case, async: false
  @moduletag :game_database
  alias TijaraTides.Infrastructure.GameServer
  alias TijaraTides.Infrastructure.Persistence.{GameStore, Repo}
  alias TijaraTides.Domain.Game
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  @endpoint TijaraTidesWeb.Endpoint

  setup_all do
    port = System.fetch_env!("TIJARA_TEST_DB_PORT") |> String.to_integer()

    start_supervised!(
      {Repo,
       hostname: "127.0.0.1",
       port: port,
       username: "postgres",
       database: "postgres",
       ssl: false,
       pool_size: 4}
    )

    Ecto.Migrator.run(Repo, TijaraTides.TestMigrations.all(), :up,
      all: true,
      log: false
    )

    :ok
  end

  setup do
    id = Ecto.UUID.generate()

    server =
      start_supervised!({GameServer, name: nil, enabled: true, world_id: id, tick_ms: 86_400_000})

    {:ok, code} = GameServer.seed(server)
    %{server: server, code: code, world_id: id}
  end

  test "full repayment is shown only when unreserved cash covers principal and interest", c do
    Application.put_env(:tijara_tides, :game_server, c.server)
    on_exit(fn -> Application.delete_env(:tijara_tides, :game_server) end)

    conn =
      build_conn() |> get("/play") |> recycle() |> post("/session/redeem", %{"code" => c.code})

    token = Plug.Conn.get_session(conn, :account_token)

    {:ok, _} =
      GameServer.command(
        token,
        "formation",
        %{"action" => "company", "name" => "Repayment UI"},
        c.server
      )

    {:ok, _} =
      GameServer.command(
        token,
        "borrow",
        %{"action" => "borrow", "amount" => 10_000_000},
        c.server
      )

    {:ok, view, _} = conn |> recycle() |> live("/play")
    assert has_element?(view, "form[phx-submit=repay]")

    {:ok, _} =
      GameServer.command(
        token,
        "purchase",
        %{
          "action" => "purchase_ship",
          "class" => "freighter",
          "port" => "Jakarta",
          "price_limit" => 4_000_000
        },
        c.server
      )

    send(view.pid, {:game_changed, 0})
    refute has_element?(view, "form[phx-submit=repay]")
    assert has_element?(view, "form[phx-submit=recast][phx-hook=LoanAmount][data-max='60000']")
    assert has_element?(view, "form[phx-submit=recast] input[type=range][max='6']")
    assert has_element?(view, "form[phx-submit=recast] input[type=number][max='60000']")
    view |> form("form[phx-submit=recast]", %{"amount" => "20000"}) |> render_submit()
    private = GameServer.snapshot(token, c.server).private
    assert private["company"]["cash"] == 4_000_000

    assert [%{"remaining" => 8_000_000, "installment" => 2_000_000} = loan] =
             private["finance"]["loans"]

    command = %{"action" => "recast", "loan" => loan["id"], "amount" => 100_000}
    assert {:ok, result} = GameServer.command(token, "recast-retry", command, c.server)
    assert {:ok, ^result} = GameServer.command(token, "recast-retry", command, c.server)

    replacement =
      start_supervised!(
        {GameServer, name: nil, enabled: true, world_id: c.world_id, tick_ms: 86_400_000},
        id: :recast_replacement
      )

    assert {:ok, ^result} = GameServer.command(token, "recast-retry", command, replacement)
    restored = GameServer.snapshot(token, replacement).private
    assert restored["company"]["cash"] == 3_900_000

    assert [%{"remaining" => 7_900_000, "installment" => 1_975_000}] =
             restored["finance"]["loans"]

    assert :ok == TijaraTides.Infrastructure.Persistence.FinancialLedger.audit(Repo, c.world_id)
  end

  test "suspension, sponsor approval, escrow release and default survive durable reload", c do
    Application.put_env(:tijara_tides, :game_server, c.server)
    on_exit(fn -> Application.delete_env(:tijara_tides, :game_server) end)

    sponsor_conn =
      build_conn() |> get("/play") |> recycle() |> post("/session/redeem", %{"code" => c.code})

    sponsor = Plug.Conn.get_session(sponsor_conn, :account_token)

    {:ok, _} =
      TijaraTides.CompanyFixture.command(
        sponsor,
        "sponsor-company",
        %{
          "action" => "company",
          "name" => "Sponsor",
          "port" => "Jakarta",
          "package" => "general"
        },
        c.server
      )

    {:ok, %{"code" => invite}} =
      GameServer.command(sponsor, "invite", %{"action" => "invite"}, c.server)

    conn =
      build_conn() |> get("/play") |> recycle() |> post("/session/redeem", %{"code" => invite})

    token = Plug.Conn.get_session(conn, :account_token)
    GameServer.connect(token, c.server)

    for n <- 1..5 do
      {:ok, _} =
        GameServer.command(
          token,
          "company-#{n}",
          %{"action" => "company", "name" => "Failed #{n}"},
          c.server
        )

      {:ok, _} =
        GameServer.command(
          token,
          "loan-#{n}",
          %{"action" => "borrow", "amount" => 10_000_000},
          c.server
        )

      for j <- 1..2 do
        {:ok, _} =
          GameServer.command(
            token,
            "ship-#{n}-#{j}",
            %{
              "action" => "purchase_ship",
              "class" => "tanker",
              "port" => "Jakarta",
              "price_limit" => 5_000_000
            },
            c.server
          )
      end

      {:ok, _} = GameServer.command(token, "bankrupt-#{n}", %{"action" => "bankruptcy"}, c.server)
      advance(c.server, 1_200_000)
    end

    private = GameServer.snapshot(token, c.server).private
    assert private["account"]["suspended_ms"] != nil
    assert private["finance"]["rate_bps"] == 1600
    {:ok, borrower_view, _} = conn |> recycle() |> live("/play")
    assert has_element?(borrower_view, "#account-suspension")
    refute has_element?(borrower_view, "#company-form")

    assert {:error, :account_suspended} =
             GameServer.command(
               token,
               "blocked",
               %{"action" => "company", "name" => "Blocked"},
               c.server
             )

    {:ok, sponsor_view, _} = sponsor_conn |> recycle() |> live("/play")
    sponsor_view |> form("form[phx-submit=guarantee]", %{"amount" => "50000"}) |> render_submit()
    refute GameServer.snapshot(token, c.server).private["account"]["suspended_ms"]

    {:ok, _} =
      GameServer.command(
        token,
        "restart",
        %{"action" => "company", "name" => "Guaranteed"},
        c.server
      )

    assert {:error, :loan_limit} =
             GameServer.command(
               token,
               "too-large",
               %{"action" => "borrow", "amount" => 5_000_001},
               c.server
             )

    {:ok, %{"loan_id" => loan}} =
      GameServer.command(
        token,
        "guaranteed-loan",
        %{"action" => "borrow", "amount" => 5_000_000},
        c.server
      )

    {:ok, _} =
      GameServer.command(token, "repay", %{"action" => "repay", "loan" => loan}, c.server)

    assert GameServer.snapshot(token, c.server).private["guarantees"]["active"] == nil
    assert GameServer.snapshot(token, c.server).private["finance"]["available"] == 0

    pledge = %{
      "action" => "guarantee",
      "account" => private["account"]["id"],
      "amount" => 5_000_000
    }

    {:ok, result} = GameServer.command(sponsor, "pledge-again", pledge, c.server)
    assert {:ok, ^result} = GameServer.command(sponsor, "pledge-again", pledge, c.server)

    {:ok, _} =
      GameServer.command(
        token,
        "loan-again",
        %{"action" => "borrow", "amount" => 5_000_000},
        c.server
      )

    {:ok, _} =
      GameServer.command(
        token,
        "buy-again",
        %{
          "action" => "purchase_ship",
          "class" => "freighter",
          "port" => "Jakarta",
          "price_limit" => 4_000_000
        },
        c.server
      )

    {:ok, _} = GameServer.command(token, "fail-again", %{"action" => "bankruptcy"}, c.server)
    assert :ok == TijaraTides.Infrastructure.Persistence.FinancialLedger.audit(Repo, c.world_id)

    replacement =
      start_supervised!(
        {GameServer, name: nil, enabled: true, world_id: c.world_id, tick_ms: 86_400_000},
        id: :guarantee_replacement
      )

    assert {:ok, ^result} = GameServer.command(sponsor, "pledge-again", pledge, replacement)
    assert GameServer.snapshot(token, replacement).private["account"]["suspended_ms"] != nil
    pledges = GameServer.snapshot(sponsor, replacement).private["guarantees"]["pledges"]
    assert Enum.any?(pledges, &(&1["status"] == "claimed" and &1["forfeited"] == 5_000_000))
    assert Enum.any?(pledges, &(&1["status"] == "released" and &1["forfeited"] == 0))
  end

  test "selling removes the ship while preserving audited history and replay after reload", c do
    {:ok, %{"session" => token}} = GameServer.redeem(c.code, c.server)

    {:ok, _} =
      GameServer.command(token, "company", %{"action" => "company", "name" => "Seller"}, c.server)

    {:ok, _} =
      GameServer.command(token, "loan", %{"action" => "borrow", "amount" => 10_000_000}, c.server)

    {:ok, %{"ship_id" => ship}} =
      GameServer.command(
        token,
        "purchase",
        %{
          "action" => "purchase_ship",
          "class" => "freighter",
          "port" => "Jakarta",
          "price_limit" => 4_000_000
        },
        c.server
      )

    GameServer.connect(token, c.server)
    advance(c.server, 60_000)
    owned = GameServer.snapshot(token, c.server).private["ships"][ship]
    assert owned["book_value"] < owned["build_value"]
    command = %{"action" => "sell_ship", "ship" => ship, "minimum" => 0}
    assert {:ok, result} = GameServer.command(token, "sale", command, c.server)
    assert {:ok, ^result} = GameServer.command(token, "sale", command, c.server)
    assert result["proceeds"] < 3_600_000
    assert GameServer.snapshot(token, c.server).private["ships"] == %{}
    assert :ok == TijaraTides.Infrastructure.Persistence.FinancialLedger.audit(Repo, c.world_id)

    replacement =
      start_supervised!(
        {GameServer, name: nil, enabled: true, world_id: c.world_id, tick_ms: 86_400_000},
        id: :sale_replacement
      )

    assert {:ok, ^result} = GameServer.command(token, "sale", command, replacement)
    assert GameServer.snapshot(token, replacement).private["ships"] == %{}
  end

  test "loan-funded ship purchases replay once and survive reload", c do
    {:ok, %{"session" => token}} = GameServer.redeem(c.code, c.server)

    assert {:ok, _} =
             GameServer.command(
               token,
               "company",
               %{"action" => "company", "name" => "Ship Buyer"},
               c.server
             )

    assert {:ok, _} =
             GameServer.command(
               token,
               "loan",
               %{"action" => "borrow", "amount" => 10_000_000},
               c.server
             )

    command = %{
      "action" => "purchase_ship",
      "class" => "freighter",
      "port" => "Jakarta",
      "price_limit" => 4_000_000
    }

    assert {:ok, result} = GameServer.command(token, "purchase", command, c.server)
    assert {:ok, ^result} = GameServer.command(token, "purchase", command, c.server)
    saved = GameServer.snapshot(token, c.server).private
    assert map_size(saved["ships"]) == 1
    assert saved["company"]["cash"] == 6_000_000
    assert :ok == TijaraTides.Infrastructure.Persistence.FinancialLedger.audit(Repo, c.world_id)

    replacement =
      start_supervised!(
        {GameServer, name: nil, enabled: true, world_id: c.world_id, tick_ms: 86_400_000},
        id: :purchase_replacement
      )

    assert GameServer.snapshot(token, replacement).private["ships"] == saved["ships"]
    assert {:ok, ^result} = GameServer.command(token, "purchase", command, replacement)
    assert GameServer.snapshot(token, replacement).private["company"]["cash"] == 6_000_000
  end

  test "finance UI, receipts, installments and bankruptcy survive durable reload", c do
    Application.put_env(:tijara_tides, :game_server, c.server)
    on_exit(fn -> Application.delete_env(:tijara_tides, :game_server) end)

    conn =
      build_conn() |> get("/play") |> recycle() |> post("/session/redeem", %{"code" => c.code})

    token = Plug.Conn.get_session(conn, :account_token)

    {:ok, %{"company_id" => company}} =
      TijaraTides.CompanyFixture.command(
        token,
        "formation",
        %{
          "action" => "company",
          "name" => "Finance Test",
          "port" => "Singapore",
          "package" => "general"
        },
        c.server
      )

    {:ok, view, _} = conn |> recycle() |> live("/play")
    assert has_element?(view, "#company-finance")
    view |> form("#loan-form", %{"amount" => "1000"}) |> render_submit()

    assert [%{"remaining" => 100_000}] =
             GameServer.snapshot(token, c.server).private["finance"]["loans"]

    request = %{"action" => "borrow", "amount" => 100_000}
    assert {:ok, reply} = GameServer.command(token, "loan-replay", request, c.server)
    assert {:ok, ^reply} = GameServer.command(token, "loan-replay", request, c.server)
    assert GameServer.snapshot(token, c.server).private["finance"]["debt"] == 200_000
    advance(c.server, 86_400_000)
    assert GameServer.snapshot(token, c.server).private["finance"]["debt"] == 150_000
    assert :ok == TijaraTides.Infrastructure.Persistence.FinancialLedger.audit(Repo, c.world_id)
    saved_loans = GameServer.snapshot(token, c.server).private["finance"]["loans"]

    assert {:error, :bankruptcy_cash_covers_debts} =
             GameServer.command(token, "solvent-close", %{"action" => "bankruptcy"}, c.server)

    {:ok, before_loss} = GameStore.claim(Repo, c.world_id)
    cash = before_loss.entities["companies"][company]["cash"]

    loss =
      before_loss
      |> put_in([:entities, "companies", company, "cash"], 0)
      |> update_in([:entities, "companies", company, "profit"], &(&1 - cash))
      |> TijaraTides.Domain.Journal.post(company, "test_loss", [
        {"crew_expense", cash},
        {"cash_available", -cash}
      ])

    assert {:ok, :ok} = GameStore.commit(Repo, c.world_id, before_loss.epoch, before_loss, loss)

    replacement =
      start_supervised!(
        {GameServer, name: nil, enabled: true, world_id: c.world_id, tick_ms: 86_400_000},
        id: :finance_replacement
      )

    assert GameServer.snapshot(token, replacement).private["finance"]["loans"] == saved_loans
    assert GameServer.snapshot(token, replacement).private["finance"]["debt"] == 150_000

    assert {:ok, result} =
             GameServer.command(token, "close-company", %{"action" => "bankruptcy"}, replacement)

    assert {:ok, ^result} =
             GameServer.command(token, "close-company", %{"action" => "bankruptcy"}, replacement)

    snapshot = GameServer.snapshot(token, replacement)
    assert snapshot.private["account"]["bankruptcies"] == 1
    assert snapshot.private["company"] == nil
    assert snapshot.private["ships"] == %{}

    assert [[2]] =
             Repo.query!(
               "SELECT count(*) FROM game_loans WHERE world_id=$1 AND status='defaulted'",
               [c.world_id]
             ).rows

    assert [[3]] =
             Repo.query!("SELECT count(*) FROM game_ships WHERE world_id=$1 AND company_id=$2", [
               c.world_id,
               company
             ]).rows

    formation = %{
      "action" => "company",
      "name" => "Fresh Start",
      "port" => "Singapore",
      "package" => "general"
    }

    assert {:error, :bankruptcy_cooldown} =
             GameServer.command(token, "too-soon", formation, replacement)

    paused_clock = GameServer.snapshot(token, replacement).public["clock_ms"]
    advance(replacement, 1_200_000)
    assert GameServer.snapshot(token, replacement).public["clock_ms"] == paused_clock
    :ok = GameServer.connect(token, replacement)
    advance(replacement, 1_200_000)

    assert {:ok, %{"company_id" => fresh}} =
             GameServer.command(token, "fresh-start", formation, replacement)

    refute fresh == company

    assert Enum.all?(GameServer.snapshot(token, replacement).private["ships"], fn {_, ship} ->
             ship["company_id"] == fresh
           end)

    assert :ok == TijaraTides.Infrastructure.Persistence.FinancialLedger.audit(Repo, c.world_id)
  end

  test "home page counts authenticated playing browsers and removes signed-out sessions", c do
    alias TijaraTides.Infrastructure.WorldServer
    Application.put_env(:tijara_tides, :game_server, c.server)
    on_exit(fn -> Application.delete_env(:tijara_tides, :game_server) end)
    :ok = WorldServer.subscribe("ocean")
    base = WorldServer.snapshot().online_players
    {:ok, lobby, _} = live(build_conn(), "/")
    {:ok, spectator, _} = live(build_conn(), "/play")
    assert WorldServer.snapshot().online_players == base

    conn =
      build_conn() |> get("/play") |> recycle() |> post("/session/redeem", %{"code" => c.code})

    token = Plug.Conn.get_session(conn, :account_token)
    {:ok, first, _} = conn |> recycle() |> live("/play")
    assert_receive {:world_updated, %{online_players: count}}
    assert count == base + 1
    {:ok, second, _} = conn |> recycle() |> live("/play")
    assert_receive {:world_updated, %{online_players: ^count}}
    assert has_element?(lobby, "#online-players", to_string(count))

    {:ok, other_code} = GameServer.seed(c.server)

    other =
      build_conn()
      |> get("/play")
      |> recycle()
      |> post("/session/redeem", %{"code" => other_code})

    {:ok, third, _} = other |> recycle() |> live("/play")
    assert_receive {:world_updated, %{online_players: two}}
    assert two == base + 2

    GenServer.stop(first.pid, :normal)
    assert_receive {:world_updated, %{online_players: ^two}}
    :ok = GameServer.sign_out(token, c.server)
    assert_receive {:world_updated, %{online_players: ^count}}
    assert has_element?(lobby, "#online-players", to_string(count))
    GenServer.stop(third.pid, :normal)
    assert_receive {:world_updated, %{online_players: ^base}}
    assert has_element?(lobby, "#online-players", to_string(base))
    Enum.each([lobby, spectator, second], &GenServer.stop(&1.pid, :normal))
  end

  test "ship instructions submit through the UI, replay, settle on arrival and survive reload",
       c do
    Application.put_env(:tijara_tides, :game_server, c.server)
    on_exit(fn -> Application.delete_env(:tijara_tides, :game_server) end)

    conn =
      build_conn() |> get("/play") |> recycle() |> post("/session/redeem", %{"code" => c.code})

    token = Plug.Conn.get_session(conn, :account_token)

    {:ok, %{"company_id" => company}} =
      TijaraTides.CompanyFixture.command(
        token,
        "company",
        %{
          "action" => "company",
          "name" => "Automatic Cargo",
          "port" => "Singapore",
          "package" => "general"
        },
        c.server
      )

    {:ok, view, _} = conn |> recycle() |> live("/play")
    instruction_form = "form[id=\"instruction-form-#{company}:1\"]"
    refute has_element?(view, instruction_form)

    assert render(view) =~
             "Choose a destination in the voyage controls before adding instructions."

    view |> form("#voyage-preview", %{"destination" => "Jakarta"}) |> render_change()
    assert has_element?(view, instruction_form, "Instructions at Jakarta")

    assert has_element?(
             view,
             instruction_form <> " option[value='aluminium_scrap']",
             "Aluminium scrap"
           )

    refute has_element?(view, instruction_form <> " select[name=port]")
    view |> form("#voyage-preview", %{"destination" => "Dubai"}) |> render_change()
    assert has_element?(view, instruction_form, "Instructions at Dubai")
    view |> form("#voyage-preview", %{"destination" => "Jakarta"}) |> render_change()
    render_change(view, "edit-instruction", %{"port" => "Dubai"})
    assert has_element?(view, instruction_form, "Instructions at Jakarta")

    view
    |> form("form[phx-submit=instruction-onward]", %{"onward" => "Singapore"})
    |> render_submit()

    assert has_element?(view, instruction_form <> " input[name=budget][disabled]")

    assert has_element?(
             view,
             instruction_form <> " input[name=quantity][max='0'][value='0'][disabled]"
           )

    assert has_element?(view, instruction_form <> " button[disabled]")

    view |> form(instruction_form, %{"side" => "buy"}) |> render_change()
    refute has_element?(view, instruction_form <> " input[name=budget][disabled]")

    assert has_element?(
             view,
             instruction_form <> " input[name=quantity]:not([max='10000']):not([disabled])"
           )

    refute has_element?(view, instruction_form <> " button[disabled]")

    view |> form(instruction_form, %{"budget" => "12000"}) |> render_change()
    view |> form(instruction_form, %{"side" => "sell"}) |> render_change()
    assert has_element?(view, instruction_form <> " input[name=budget][disabled]")
    view |> form(instruction_form, %{"side" => "buy"}) |> render_change()

    assert has_element?(
             view,
             instruction_form <> " input[name=budget][value='12000']:not([disabled])"
           )

    view
    |> form("form[id=\"instruction-form-#{company}:1\"]", %{
      "side" => "buy",
      "good" => "lumber",
      "quantity" => "2",
      "limit" => "10000",
      "budget" => "10000",
      "onward" => "Singapore"
    })
    |> render_change()

    send(view.pid, {:game_changed, 0})

    assert has_element?(
             view,
             "form[id=\"instruction-form-#{company}:1\"] input[name=quantity][value=\"2\"]"
           )

    assert has_element?(
             view,
             "form[id=\"instruction-form-#{company}:1\"]",
             "Instructions at Jakarta"
           )

    view
    |> form("form[id=\"instruction-form-#{company}:1\"]", %{
      "side" => "buy",
      "good" => "lumber",
      "quantity" => "2",
      "limit" => "10000",
      "budget" => "10000",
      "onward" => "Singapore"
    })
    |> render_submit()

    [order] = GameServer.snapshot(token, c.server).private["ship_instructions"] |> Map.values()
    assert order["port"] == "Jakarta"
    assert order["limit"] == 1_000_000
    assert order["status"] == "planned"
    assert render(view) =~ "0/2 lots"
    assert has_element?(view, "form[phx-submit=instruction-onward]")

    {:ok, %{"instruction_id" => second_buy}} =
      GameServer.command(
        token,
        "second-buy",
        %{
          "action" => "instruction",
          "ship" => company <> ":1",
          "port" => "Jakarta",
          "side" => "buy",
          "good" => "lumber",
          "quantity" => 1,
          "limit" => 1_000_000,
          "budget" => 1_000_000,
          "onward" => "Singapore"
        },
        c.server
      )

    view |> form("form[phx-submit=instruction-onward]", %{"onward" => "Dubai"}) |> render_submit()

    assert Enum.all?(GameServer.snapshot(token, c.server).private["ship_instructions"], fn {_,
                                                                                            row} ->
             row["onward"] == "Dubai"
           end)

    assert {:error, :instruction_onward_conflict} =
             GameServer.command(
               token,
               "conflicting-buy",
               %{
                 "action" => "instruction",
                 "ship" => company <> ":1",
                 "port" => "Jakarta",
                 "side" => "buy",
                 "good" => "lumber",
                 "quantity" => 1,
                 "limit" => 1_000_000,
                 "budget" => 1_000_000,
                 "onward" => "Singapore"
               },
               c.server
             )

    shared = %{
      "action" => "instruction_onward",
      "ship" => company <> ":1",
      "port" => "Jakarta",
      "onward" => "Singapore"
    }

    assert {:ok, shared_reply} = GameServer.command(token, "shared-return", shared, c.server)
    revision = GameServer.snapshot(token, c.server).public["revision"]
    assert {:ok, ^shared_reply} = GameServer.command(token, "shared-return", shared, c.server)
    assert GameServer.snapshot(token, c.server).public["revision"] == revision

    assert [["Singapore"], ["Singapore"]] ==
             Repo.query!(
               "SELECT onward_port_id FROM game_ship_instructions WHERE world_id=$1 ORDER BY id",
               [c.world_id]
             ).rows

    assert {:ok, _} =
             GameServer.command(
               token,
               "cancel-second-buy",
               %{"action" => "cancel_instruction", "instruction" => second_buy},
               c.server
             )

    command = %{
      "action" => "instruction",
      "ship" => company <> ":1",
      "port" => "Jakarta",
      "side" => "buy",
      "good" => "lumber",
      "quantity" => 1,
      "limit" => 1_000_000,
      "budget" => 1_000_000,
      "onward" => "Singapore"
    }

    assert {:ok, reply} = GameServer.command(token, "replay-order", command, c.server)
    assert {:ok, ^reply} = GameServer.command(token, "replay-order", command, c.server)
    assert map_size(GameServer.snapshot(token, c.server).private["ship_instructions"]) == 3
    view |> element("#instruction-#{reply["instruction_id"]} button") |> render_click()

    quote = GameServer.preview(token, company <> ":1", "Jakarta", c.server)

    assert {:ok, _} =
             GameServer.command(
               token,
               "sail",
               %{
                 "action" => "sail",
                 "ship" => company <> ":1",
                 "destination" => "Jakarta",
                 "fuel_limit" => quote["fuel"]
               },
               c.server
             )

    :sys.replace_state(c.server, fn state ->
      %{state | last_mono: System.monotonic_time(:millisecond) - quote["duration_ms"] - 1}
    end)

    send(c.server, :tick)
    snapshot = GameServer.snapshot(token, c.server)
    assert snapshot.private["ship_instructions"][order["id"]]["filled"] == 2
    assert snapshot.private["ships"][company <> ":1"]["status"] == "loading"

    assert [[1]] =
             Repo.query!(
               "SELECT count(*) FROM game_journal_transactions WHERE world_id=$1 AND kind='purchase'",
               [c.world_id]
             ).rows

    replacement =
      start_supervised!(
        {GameServer, name: nil, enabled: true, world_id: c.world_id, tick_ms: 86_400_000},
        id: :instruction_replacement
      )

    restored = GameServer.snapshot(token, replacement)
    assert restored.private["ship_instructions"] == snapshot.private["ship_instructions"]
    assert restored.private["ships"] == snapshot.private["ships"]
    assert GameServer.snapshot(nil, replacement).private == nil

    assert [[1]] =
             Repo.query!(
               "SELECT count(*) FROM game_journal_transactions WHERE world_id=$1 AND kind='purchase'",
               [c.world_id]
             ).rows
  end

  test "a fenced progression tick cannot advance durable state or publish a revision", %{
    server: server,
    code: code,
    world_id: world
  } do
    {:ok, %{"session" => token}} = GameServer.redeem(code, server)
    assert :ok = GameServer.connect(token, server)
    before = :sys.get_state(server)
    # A second owner claims the actual SQL epoch, fencing this still-live server.
    assert {:ok, claimed} = GameStore.claim(Repo, world)
    assert claimed.epoch == before.game.epoch + 1
    GameServer.subscribe()

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert %{status: :unavailable} = advance(server, 5000)
      end)

    assert log =~ "ownership_lost"
    stopped = :sys.get_state(server)
    refute stopped.active
    assert stopped.game == before.game
    assert stopped.projection == before.projection
    refute_receive {:game_changed, _}, 10

    assert [[claimed.clock_ms, claimed.revision]] ==
             Repo.query!(
               "SELECT clock_ms,revision FROM game_worlds WHERE id=$1",
               [world]
             ).rows

    send(server, :tick)
    assert GameServer.readiness(server) == :unavailable
    assert :sys.get_state(server).game == before.game
  end

  for auto_depart <- [false, true] do
    test "cargo-free onward plan survives restart with automatic departure #{auto_depart}",
         c do
      {:ok, %{"session" => token}} = GameServer.redeem(c.code, c.server)

      {:ok, %{"company_id" => company}} =
        TijaraTides.CompanyFixture.command(
          token,
          "company",
          %{
            "action" => "company",
            "name" => "Deadhead",
            "port" => "Singapore",
            "package" => "general"
          },
          c.server
        )

      {:ok, _} =
        GameServer.command(
          token,
          "plan",
          %{
            "action" => "instruction_onward",
            "ship" => company <> ":1",
            "port" => "Jakarta",
            "onward" => "Singapore",
            "auto_depart" => unquote(auto_depart)
          },
          c.server
        )

      replacement =
        start_supervised!(
          {GameServer, name: nil, enabled: true, world_id: c.world_id, tick_ms: 86_400_000},
          id: :deadhead_replacement
        )

      Application.put_env(:tijara_tides, :game_server, replacement)
      on_exit(fn -> Application.delete_env(:tijara_tides, :game_server) end)
      snapshot = GameServer.snapshot(token, replacement)
      assert snapshot.private["ship_instructions"] == %{}
      assert snapshot.private["visit_plans"][company <> ":1|Jakarta"]["onward"] == "Singapore"
      conn = build_conn() |> init_test_session(%{account_token: token})
      {:ok, view, _} = live(conn, "/play")
      view |> form("#voyage-preview", %{"destination" => "Jakarta"}) |> render_change()

      assert has_element?(
               view,
               "form[phx-submit=instruction-onward]",
               "Onward destination after Jakarta"
             )

      selector = "form[phx-submit=instruction-onward] input[type=checkbox][name=auto_depart]"
      assert has_element?(view, selector <> "[checked]") == unquote(auto_depart)

      view
      |> form("form[phx-submit=instruction-onward]", %{
        "onward" => "Singapore",
        "auto_depart" => "false"
      })
      |> render_submit()

      refute GameServer.snapshot(token, replacement).private["visit_plans"][
               company <> ":1|Jakarta"
             ]["auto_depart"]

      view
      |> form("form[phx-submit=instruction-onward]", %{
        "onward" => "Singapore",
        "auto_depart" => to_string(unquote(auto_depart))
      })
      |> render_submit()

      assert GameServer.snapshot(token, replacement).private["visit_plans"][
               company <> ":1|Jakarta"
             ]["auto_depart"] == unquote(auto_depart)

      quote = GameServer.preview(token, company <> ":1", "Jakarta", replacement)
      view |> element("button[phx-click=sail]") |> render_click()
      advance(replacement, quote["duration_ms"] + 1)

      unless unquote(auto_depart),
        do: assert(has_element?(view, "#voyage-preview option[value=Singapore][selected]"))

      assert GameServer.snapshot(token, replacement).private["ships"][company <> ":1"]["cargo"] ==
               []

      unless unquote(auto_depart), do: view |> element("button[phx-click=sail]") |> render_click()
      returning = GameServer.snapshot(token, replacement)
      assert returning.private["ships"][company <> ":1"]["destination"] == "Singapore"
      assert returning.private["ships"][company <> ":1"]["status"] == "sailing"
      assert returning.private["visit_plans"] == %{}
    end
  end

  test "invalid preview destinations leave the shared owner available", %{
    server: server,
    code: code
  } do
    {:ok, %{"session" => token}} = GameServer.redeem(code, server)

    {:ok, %{"company_id" => company}} =
      TijaraTides.CompanyFixture.command(
        token,
        "company",
        %{
          "action" => "company",
          "name" => "Preview Safety",
          "port" => "Jakarta",
          "package" => "general"
        },
        server
      )

    for destination <- [nil, %{}, [], 42, "not-a-port"] do
      assert GameServer.preview(token, company <> ":1", destination, server) == nil
      assert Process.alive?(server)
      assert GameServer.readiness(server) == :ready
    end

    assert is_map(GameServer.preview(token, company <> ":1", "Singapore", server))
  end

  test "a dropped redemption response is recoverable only with the original device cookie across restart",
       %{server: server, code: code, world_id: world} do
    Application.put_env(:tijara_tides, :game_server, server)
    on_exit(fn -> Application.delete_env(:tijara_tides, :game_server) end)
    form_conn = get(build_conn(), "/play")
    device = Plug.Conn.get_session(form_conn, :redemption_token)
    assert is_binary(device)

    response = form_conn |> recycle() |> post("/session/redeem", %{"code" => code})
    assert Plug.Conn.get_session(response, :account_token) == device
    assert Plug.Conn.get_session(response, :redemption_token) == nil
    account_id = GameServer.snapshot(device, server).private["account"]["id"]

    replacement =
      start_supervised!({GameServer, name: nil, enabled: true, world_id: world},
        id: :redemption_replacement
      )

    Application.put_env(:tijara_tides, :game_server, replacement)
    revision = :sys.get_state(replacement).game.revision

    # Discard the POST response cookie; retry using only the pre-submit cookie.
    retry = form_conn |> recycle() |> post("/session/redeem", %{"code" => code})
    assert Plug.Conn.get_session(retry, :account_token) == device
    assert GameServer.snapshot(device, replacement).private["account"]["id"] == account_id
    assert :sys.get_state(replacement).game.revision == revision

    assert [[1]] =
             Repo.query!("SELECT count(*) FROM game_accounts WHERE world_id=$1", [world]).rows

    assert [[1]] =
             Repo.query!("SELECT count(*) FROM game_sessions WHERE world_id=$1", [world]).rows

    stranger =
      build_conn() |> get("/play") |> recycle() |> post("/session/redeem", %{"code" => code})

    assert Plug.Conn.get_session(stranger, :account_token) == nil
    assert :ok = GameServer.sign_out(device, replacement)
    revoked = form_conn |> recycle() |> post("/session/redeem", %{"code" => code})
    assert Plug.Conn.get_session(revoked, :account_token) == nil
    assert GameServer.snapshot(device, replacement).private == nil
  end

  test "redemption requires a delivered cookie and same-device retries create only one account",
       %{server: server, code: code, world_id: world} do
    Application.put_env(:tijara_tides, :game_server, server)
    on_exit(fn -> Application.delete_env(:tijara_tides, :game_server) end)
    response = post(build_conn(), "/session/redeem", %{"code" => code})
    assert Plug.Conn.get_session(response, :account_token) == nil

    assert [[0]] =
             Repo.query!("SELECT count(*) FROM game_accounts WHERE world_id=$1", [world]).rows

    device = GameServer.token()

    results =
      1..8
      |> Task.async_stream(fn _ -> GameServer.redeem_for_device(code, device, server) end,
        max_concurrency: 8
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &match?({:ok, %{"session" => ^device}}, &1))
    assert results |> Enum.uniq() |> length() == 1
    {:ok, another_code} = GameServer.seed(server)

    assert {:error, :invalid_invitation} =
             GameServer.redeem_for_device(another_code, device, server)

    assert [[1]] =
             Repo.query!("SELECT count(*) FROM game_accounts WHERE world_id=$1", [world]).rows
  end

  test "release checks and migrations leave world ownership unchanged", %{
    server: server,
    world_id: world
  } do
    previous = Application.get_env(:tijara_tides, Repo)
    previous_enabled = Application.get_env(:tijara_tides, :start_repo)
    Application.put_env(:tijara_tides, :start_repo, true)

    Application.put_env(:tijara_tides, Repo,
      hostname: "127.0.0.1",
      port: String.to_integer(System.fetch_env!("TIJARA_TEST_DB_PORT")),
      database: "postgres",
      username: "postgres",
      ssl: false
    )

    on_exit(fn ->
      if previous == nil,
        do: Application.delete_env(:tijara_tides, Repo),
        else: Application.put_env(:tijara_tides, Repo, previous)

      Application.put_env(:tijara_tides, :start_repo, previous_enabled)
    end)

    before = :sys.get_state(server).game.epoch

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert :ok = TijaraTides.Release.check_database()
        assert [] = TijaraTides.Release.migrate()
      end)

    assert output =~ "127.0.0.1:"
    assert output =~ "/postgres"

    assert [[^before]] =
             Repo.query!("SELECT epoch FROM game_worlds WHERE id=$1", [world]).rows

    assert GameServer.readiness(server) == :ready
  end

  # Covers the outer receipt lookup. The transaction-level replay shares its
  # decorator, but injecting a receipt between the two lookups is deliberately
  # outside this test's scope.
  test "legacy invitation receipts replay the original code after subkey derivation", %{
    server: server,
    code: code
  } do
    {:ok, %{"session" => token}} = GameServer.redeem(code, server)
    state = :sys.get_state(server)

    {:ok, account} =
      Game.authenticate(state.game, GameServer.hash(token), System.system_time(:millisecond))

    request = "legacy-invite"
    command = %{"action" => "invite"}

    legacy =
      :crypto.mac(
        :hmac,
        :sha256,
        Application.fetch_env!(:tijara_tides, :game_secret),
        "invite:" <> account["id"] <> ":" <> request
      )
      |> Base.url_encode64(padding: false)

    context = %{id: "legacy", invite_hash: GameServer.hash(legacy)}
    {:ok, game, result} = Game.execute(state.game, account, command, context, state.catalogue)
    receipt = {account["id"], request, GameServer.hash(:erlang.term_to_binary(command)), result}

    assert {:ok, :ok} =
             GameStore.commit(Repo, state.world_id, game.epoch, state.game, game, receipt)

    :sys.replace_state(server, &%{&1 | game: TijaraTides.Domain.Journal.clear(game)})
    assert {:ok, %{"code" => ^legacy}} = GameServer.command(token, request, command, server)
  end

  test "integrity failures are logged and reported distinctly from database outages", %{
    server: server,
    code: code
  } do
    {:ok, %{"session" => token}} = GameServer.redeem(code, server)

    {:ok, _} =
      TijaraTides.CompanyFixture.command(
        token,
        "create",
        %{
          "action" => "company",
          "name" => "Integrity Shipping",
          "port" => "Jakarta",
          "package" => "general"
        },
        server
      )

    state = :sys.get_state(server)

    Repo.query!(
      "UPDATE game_companies SET cash_cents = cash_cents + 1 WHERE world_id = $1",
      [state.world_id]
    )

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, :internal_error} = GameServer.seed(server)
      end)

    assert log =~ "ArgumentError"
    assert log =~ "financial_ledger.ex"
    refute log =~ token
    assert GameServer.readiness(server) == :unavailable
  end

  test "concurrent redemption creates one account and one session", %{
    server: server,
    code: code,
    world_id: world
  } do
    results =
      1..8
      |> Task.async_stream(fn _ -> GameServer.redeem(code, server) end, max_concurrency: 8)
      |> Enum.map(fn {:ok, r} -> r end)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1

    assert [[1]] =
             Repo.query!(
               "SELECT count(*) FROM game_accounts WHERE world_id=$1",
               [world]
             ).rows

    assert [[1]] =
             Repo.query!(
               "SELECT count(*) FROM game_sessions WHERE world_id=$1",
               [world]
             ).rows
  end

  test "authenticated reconnect repairs a missing world timer without duplicate ticks", %{
    server: server,
    code: code
  } do
    {:ok, %{"session" => token}} = GameServer.redeem(code, server)
    :ok = GameServer.connect(token, server)
    original = :sys.get_state(server).timer
    Process.cancel_timer(original)
    :ok = GameServer.connect(token, server)
    repaired = :sys.get_state(server).timer
    assert repaired != original
    assert is_integer(Process.read_timer(repaired))
    :ok = GameServer.connect(token, server)
    assert :sys.get_state(server).timer == repaired

    before = GameServer.snapshot(token, server)
    send(server, {:timeout, original, :tick})
    assert GameServer.snapshot(token, server) == before
    send(server, {:timeout, repaired, :tick})
    assert GameServer.snapshot(token, server).public["revision"] > before.public["revision"]
    assert :sys.get_state(server).timer != repaired
  end

  test "command retries create one empty company, preserve balances, and reject request conflicts",
       %{
         server: server,
         code: code
       } do
    {:ok, %{"session" => token}} = GameServer.redeem(code, server)

    command = %{
      "action" => "company",
      "name" => "Durable Shipping",
      "port" => "Jakarta",
      "package" => "general"
    }

    request = GameServer.request_id()
    assert {:ok, result} = GameServer.command(token, request, command, server)
    before = GameServer.snapshot(token, server)
    assert {:ok, ^result} = GameServer.command(token, request, command, server)
    assert GameServer.snapshot(token, server) == before
    assert map_size(before.private["ships"]) == 0

    assert {:error, :request_conflict} =
             GameServer.command(token, request, %{command | "name" => "Different"}, server)
  end

  test "invitation retry returns the same usable code and revocation removes access", %{
    server: server,
    code: code
  } do
    {:ok, %{"session" => token}} = GameServer.redeem(code, server)
    request = GameServer.request_id()
    assert {:ok, result} = GameServer.command(token, request, %{"action" => "invite"}, server)
    assert {:ok, ^result} = GameServer.command(token, request, %{"action" => "invite"}, server)
    assert {:ok, _} = GameServer.redeem(result["code"], server)
    assert GameServer.snapshot(token, server).private["account"]["invite_quota"] == 2
    GameServer.sign_out(token, server)
    assert GameServer.snapshot(token, server).private == nil

    assert {:error, :invalid_session} =
             GameServer.command(token, "after-signout", %{"action" => "invite"}, server)
  end

  test "restart restores ownership and state without offline catch-up; old owner is fenced", %{
    server: server,
    code: code,
    world_id: world
  } do
    {:ok, %{"session" => token}} = GameServer.redeem(code, server)

    {:ok, _} =
      TijaraTides.CompanyFixture.command(
        token,
        "company",
        %{
          "action" => "company",
          "name" => "Restored",
          "port" => "Jakarta",
          "package" => "general"
        },
        server
      )

    before = GameServer.snapshot(token, server)

    new =
      start_supervised!({GameServer, name: nil, enabled: true, world_id: world}, id: :new_owner)

    assert GameServer.snapshot(token, new) == before

    assert {:error, :ownership_lost} =
             GameServer.command(token, "invite", %{"action" => "invite"}, server)

    assert GameServer.snapshot(token, server).status == :unavailable
    assert GameServer.snapshot(token, new) == before
  end

  test "failed transaction rolls back changed entities and receipt together", %{world_id: world} do
    {:ok, before} = GameStore.claim(Repo, world)
    {:ok, changed, _} = Game.seed_invite(before, "rollback-probe")

    assert_raise Postgrex.Error, fn ->
      GameStore.commit(
        Repo,
        world,
        before.epoch,
        before,
        changed,
        {"account", "request", nil, %{}}
      )
    end

    assert [] ==
             Repo.query!(
               "SELECT id FROM game_invitations WHERE world_id=$1 AND id='rollback-probe'",
               [
                 world
               ]
             ).rows

    assert [] ==
             Repo.query!("SELECT request_id FROM game_receipts WHERE world_id=$1", [world]).rows
  end

  test "browser can redeem, form a company, buy, sail, sell and reconnect", %{
    server: server,
    code: code
  } do
    Application.put_env(:tijara_tides, :game_server, server)
    on_exit(fn -> Application.delete_env(:tijara_tides, :game_server) end)
    conn = build_conn() |> get("/play") |> recycle() |> post("/session/redeem", %{"code" => code})
    assert redirected_to(conn) == "/play"
    token = Plug.Conn.get_session(conn, :account_token)
    assert is_binary(token)
    {:ok, view, _} = conn |> recycle() |> live("/play")

    view |> form("#company-form", %{"name" => "Browser Shipping"}) |> render_change()
    assert has_element?(view, "#company-form input[name=name][value='Browser Shipping']")
    view |> form("#company-form", %{"name" => "Browser Shipping"}) |> render_submit()
    empty = GameServer.snapshot(token, server)
    assert empty.private["ships"] == %{}
    assert empty.private["company"]["cash"] == 0
    assert empty.private["finance"]["available"] == 25_000_000
    assert has_element?(view, "#shipyard-freighter button[disabled]")
    view |> form("#loan-form", %{"amount" => "200000"}) |> render_submit()
    render_change(view, "port", %{"id" => "Jakarta"})
    for _ <- 1..3, do: view |> form("#shipyard-freighter") |> render_submit()
    assert map_size(GameServer.snapshot(token, server).private["ships"]) == 3

    assert render(view) =~ "Browser Shipping"
    render_change(view, "market-good", %{"good" => "spices"})
    refute has_element?(view, "#cargo-supply tr[data-port=Dubai]")
    render_change(view, "market-good", %{"good" => "appliances"})
    refute has_element?(view, "#cargo-demand tr[data-port='Colón']")
    refute has_element?(view, "#cargo-supply tr[data-port='Colón']")
    refute has_element?(view, "#cargo-markets", "Trading not available yet")
    assert has_element?(view, "#ports-panel #port-selector")
    assert has_element?(view, "#ships-panel #world-map")
    assert has_element?(view, "#cargo-panel #cargo-markets")
    view |> element("#market-good") |> render_click()
    assert has_element?(view, "#market-good[aria-expanded=true]")
    send(view.pid, {:game_changed, 0})
    assert has_element?(view, "#cargo-options .cargo-spread")

    option_goods = fn ->
      render(view)
      |> LazyHTML.from_document()
      |> LazyHTML.query("#cargo-options button")
      |> LazyHTML.attribute("phx-value-good")
    end

    alphabetical = option_goods.()
    assert has_element?(view, "#cargo-ship-filter input[type=checkbox]:not([checked])")
    assert "crude_oil" in alphabetical
    view |> form("#cargo-ship-filter", %{"compatible" => "true"}) |> render_change()
    assert has_element?(view, "#cargo-ship-filter input[type=checkbox][checked]")
    assert "lumber" in option_goods.()
    refute "crude_oil" in option_goods.()
    refute "fruit" in option_goods.()
    send(view.pid, {:game_changed, 0})
    refute "crude_oil" in option_goods.()
    view |> form("#cargo-ship-filter", %{"compatible" => "false"}) |> render_change()
    assert option_goods.() == alphabetical

    markets = GameServer.snapshot(token, server).markets

    expected =
      Enum.sort_by(alphabetical, fn good ->
        quotes =
          for {key, quote} <- markets,
              String.ends_with?(key, "|" <> good),
              quote["manual"],
              do: quote

        asks = for quote <- quotes, quote["stock"] > 0, do: quote["ask"]
        bids = for quote <- quotes, quote["demand"] > 0, do: quote["bid"]

        roi =
          if asks != [] and bids != [] and Enum.min(asks) > 0,
            do: (Enum.max(bids) - Enum.min(asks)) / Enum.min(asks)

        {is_nil(roi), -(roi || 0), Enum.find_index(alphabetical, &(&1 == good))}
      end)

    # These untouched markets share the same ROI, so sorting has no useful effect.
    refute has_element?(view, "#cargo-sort")
    render_change(view, "cargo-sort-roi", %{"roi" => "true"})
    assert option_goods.() == expected
    send(view.pid, {:game_changed, 0})
    assert option_goods.() == expected
    render_change(view, "cargo-sort-roi", %{"roi" => "false"})
    assert option_goods.() == alphabetical
    view |> element("#cargo-options button[phx-value-good='aluminium_scrap']") |> render_click()
    refute has_element?(view, "#cargo-options")
    view |> element("#market-good") |> render_click()
    render_click(view, "close-cargo-menu")
    refute has_element?(view, "#cargo-options")
    assert has_element?(view, "#market-good", "Aluminium scrap")
    assert has_element?(view, "#cargo-supply th[aria-sort=ascending]", "Buy price")
    assert has_element?(view, "#cargo-markets tr[data-port='Singapore'] td", "500")
    assert has_element?(view, "#cargo-supply tr[data-port='Singapore']")
    refute has_element?(view, "#cargo-demand tr[data-port='Singapore']")
    assert has_element?(view, "#cargo-demand th[aria-sort=descending]", "Sell price")
    view |> element("#cargo-markets button[phx-value-column=stock]") |> render_click()
    send(view.pid, {:game_changed, 0})
    assert has_element?(view, "#market-good", "Aluminium scrap")
    assert has_element?(view, "#cargo-supply th[aria-sort=ascending]", "Supply")
    view |> element("#cargo-markets button[phx-value-id='Singapore']") |> render_click()
    assert has_element?(view, "#port-selector[data-selected='Singapore']")
    assert has_element?(view, "#destination-planner", "From Jakarta")
    assert has_element?(view, "#destination-planner tr[data-good=lumber]", "$225")
    assert has_element?(view, "#destination-planner tr[data-good=lumber]", "$275")
    assert has_element?(view, "#destination-planner tr[data-good='iron_ore']", "No demand")
    view |> element("#set-port-destination") |> render_click()
    assert has_element?(view, "#voyage-preview option[selected]", "Singapore")
    assert has_element?(view, "#port-selector[data-selected='Singapore']")
    assert has_element?(view, "#set-port-destination[disabled]", "Selected destination")
    assert has_element?(view, "button[phx-click=sail]", "Reserve fuel and sail")

    assert Enum.all?(GameServer.snapshot(token, server).private["ships"], fn {_, ship} ->
             ship["status"] == "docked"
           end)

    render_change(view, "preview", %{"destination" => ""})
    render_click(view, "market-good", %{"good" => "lumber"})

    snapshot = GameServer.snapshot(token, server)
    ship = snapshot.private["ships"] |> Map.values() |> Enum.sort_by(& &1["id"]) |> hd()
    other_ship = snapshot.private["ships"] |> Map.values() |> Enum.find(&(&1["id"] != ship["id"]))
    assert has_element?(view, "#cargo-demand button[phx-value-column=distance]", "nm")
    catalogue = GameServer.definitions().catalogue

    expected =
      snapshot.markets
      |> Enum.filter(fn {key, quote} ->
        String.ends_with?(key, "|lumber") && quote["manual"] && quote["demand"] > 0
      end)
      |> Enum.sort_by(fn {key, quote} ->
        port = String.replace_suffix(key, "|lumber", "")

        {-quote["bid"], -quote["demand"],
         catalogue["routes"]["Jakarta|" <> port]["nautical_miles"], port}
      end)
      |> Enum.map(fn {key, _} -> String.replace_suffix(key, "|lumber", "") end)

    actual =
      render(view)
      |> LazyHTML.from_document()
      |> LazyHTML.query("#cargo-demand tr[data-port]")
      |> LazyHTML.attribute("data-port")

    assert actual == expected
    render_click(view, "ship", %{"id" => other_ship["id"]})

    refute has_element?(view, "#world-map [phx-click=inspect-ship][phx-value-id='#{ship["id"]}']")

    view
    |> element("#port-traffic [phx-click=inspect-ship][phx-value-id='#{ship["id"]}']")
    |> render_click()

    assert has_element?(
             view,
             "button[phx-click=ship][phx-value-id='#{ship["id"]}'][aria-pressed=true]"
           )

    assert has_element?(
             view,
             "button[phx-click=ship][phx-value-id='#{other_ship["id"]}'][aria-pressed=false]"
           )

    assert has_element?(view, "#map-ship-overlay", ship["name"])
    assert has_element?(view, "#map-ship-overlay", "Cargo aboard")
    assert has_element?(view, "h3", "#{ship["name"]} — Manifest")
    refute has_element?(view, "#public-ship-inspector")

    render_click(view, "map-region", %{"id" => "Pearl River Delta"})
    assert has_element?(view, "#region-ports button", "Guangzhou")
    assert has_element?(view, "#region-ports button", "Hong Kong")
    assert has_element?(view, "#region-ports button", "Shenzhen")
    refute has_element?(view, "#world-map[viewBox='0 0 1000 500']")
    render_click(view, "port", %{"id" => "Hong Kong"})
    assert has_element?(view, "#port-selector[data-selected='Hong Kong']")
    assert has_element?(view, "#region-ports button[aria-pressed=true]", "Hong Kong")
    send(view.pid, {:game_changed, 0})
    assert has_element?(view, "#region-ports", "Pearl River Delta")
    render_click(view, "map-world")
    refute has_element?(view, "#region-ports")
    assert has_element?(view, "#world-map[viewBox='0 0 1000 500']")
    render_change(view, "port", %{"id" => "Tokyo"})
    assert has_element?(view, "th", "Buy / supply")
    refute has_element?(view, "th", "Aboard")
    refute has_element?(view, "th", "Trade")
    refute has_element?(view, "[id^=aboard-]")
    render_change(view, "port", %{"id" => "Jakarta"})
    assert has_element?(view, "th", "Aboard")
    assert has_element?(view, "th", "Trade")
    refute has_element?(view, "td", "Appliances")
    refute has_element?(view, "td", "Fruit")
    assert has_element?(view, "td", "Lumber")
    assert has_element?(view, "#aboard-lumber", "0")
    refute has_element?(view, "#set-port-destination")
    render_change(view, "market-good", %{"good" => "grain"})

    view
    |> element("#port-market-table button[phx-click=market-good][phx-value-good=lumber]")
    |> render_click()

    assert has_element?(view, "#market-good", "Lumber")
    assert has_element?(view, "#cargo-supply tr[data-port=Jakarta]")
    assert has_element?(view, "#cargo-demand tr[data-port=Singapore]")
    assert has_element?(view, "#port-market-table th", "Buy / supply")
    refute has_element?(view, "#port-market-table th", "Sell / demand")
    refute has_element?(view, "#port-market-table form[phx-submit=trade] input[value=sell]")
    assert has_element?(view, "#trade-buy-lumber button[disabled]")
    assert has_element?(view, "#quantity-buy-lumber[value='0'][max='0'][disabled]")
    assert has_element?(view, "#aboard-lumber", "0")
    render_change(view, "preview", %{"destination" => "Singapore"})
    assert has_element?(view, "#port-selector[data-selected='Jakarta']")
    assert has_element?(view, "#voyage-preview option[selected]", "Singapore")

    assert has_element?(
             view,
             "button[phx-click=port-market-side][phx-value-side=buy][aria-pressed=true]"
           )

    assert_push_event(view, "workspace-panel", %{panel: 0})
    assert has_element?(view, "#purchase-voyage-summary", "Singapore")
    assert has_element?(view, "#purchase-voyage-summary", "estimated fleet upkeep")

    limit =
      GameServer.trade_limits(GameServer.snapshot(token, server), ship, "Singapore")[
        {"buy", "lumber"}
      ]

    assert limit > 0
    assert has_element?(view, "#quantity-buy-lumber[value='#{limit}'][max='#{limit}']")

    assert has_element?(
             view,
             "#trade-buy-lumber input[type=range][value='#{limit}'][max='#{limit}']"
           )

    assert has_element?(view, "#destination-market-note", "Singapore")
    assert has_element?(view, ".destination-bid[data-good=lumber]", "$275 bid")
    assert has_element?(view, ".destination-bid[data-good=lumber]", "+$50 gross profit / lot")
    assert has_element?(view, ".destination-bid[data-good=lumber] .destination-profit")
    refute has_element?(view, ".destination-bid[data-good='iron_ore']")

    render_change(view, "trade-preview", %{
      "action" => "buy",
      "destination" => "Singapore",
      "good" => "lumber",
      "quantity" => "500"
    })

    assert has_element?(view, "#quantity-buy-lumber[value='#{limit}']")
    refute has_element?(view, "#trade-buy-lumber .purchase-total.text-red-400")

    render_change(view, "trade-preview", %{
      "action" => "buy",
      "destination" => "Singapore",
      "good" => "lumber",
      "quantity" => "10"
    })

    assert has_element?(view, "#trade-buy-lumber .purchase-total", "$2270 total")
    assert has_element?(view, "#purchase-voyage-summary", "For 10 lots of Lumber")
    refute has_element?(view, "#port-market-table .purchase-voyage")
    refute has_element?(view, "#trade-buy-lumber .purchase-total.text-red-400")

    assert render(view) =~ "900 m³"
    assert render(view) =~ "1.6 m³"
    assert has_element?(view, "#quantity-buy-lumber[value='10']")

    render_submit(view, "trade", %{
      "action" => "buy",
      "destination" => "Singapore",
      "good" => "lumber",
      "quantity" => "10",
      "limit" => "30000"
    })

    assert GameServer.snapshot(token, server).private["ships"][ship["id"]]["status"] == "loading"
    render_change(view, "fleet-status", %{"status" => "docked"})
    refute has_element?(view, ".fleet-list button[phx-value-id='#{ship["id"]}']")
    assert has_element?(view, ".fleet-list button[phx-value-id='#{other_ship["id"]}']")
    send(view.pid, {:game_changed, 0})
    assert has_element?(view, "#fleet-status option[selected]", "Docked")
    {:ok, fresh_view, _} = conn |> recycle() |> live("/play")

    refute has_element?(
             fresh_view,
             ".fleet-list button[phx-value-id='#{ship["id"]}'][aria-pressed=true]"
           )

    assert has_element?(fresh_view, ".fleet-list button[aria-pressed=true]", "docked")
    assert has_element?(fresh_view, "#port-selector[data-selected='Jakarta']")
    GenServer.stop(fresh_view.pid)
    render_change(view, "fleet-status", %{"status" => "all"})
    refute has_element?(view, "#set-port-destination")
    assert has_element?(view, "#aboard-lumber", "10")
    assert render(view) =~ "16 m³"
    refute has_element?(view, "td", "Appliances")
    advance(server, 6000)
    {:ok, loaded_startup, _} = conn |> recycle() |> live("/play")

    refute has_element?(
             loaded_startup,
             ".fleet-list button[phx-value-id='#{ship["id"]}'][aria-pressed=true]"
           )

    assert has_element?(loaded_startup, ".fleet-list button[aria-pressed=true]", "docked")
    GenServer.stop(loaded_startup.pid)

    assert has_element?(
             view,
             ".fleet-list button[phx-value-id='#{ship["id"]}'][aria-pressed=true]"
           )

    refute has_element?(view, "td", "Appliances")
    new_ship = GameServer.snapshot(token, server).private["ships"][ship["id"]]

    new_limit =
      GameServer.trade_limits(GameServer.snapshot(token, server), new_ship, "Singapore")[
        {"buy", "lumber"}
      ]

    assert has_element?(view, "#quantity-buy-lumber[value='#{new_limit}']")
    assert has_element?(view, "button[phx-click=sail]", "Reserve fuel and sail")
    assert has_element?(view, "#voyage-preview option[selected]", "Singapore")

    render_submit(view, "trade", %{
      "action" => "buy",
      "destination" => "Singapore",
      "good" => "lumber",
      "quantity" => "1",
      "limit" => "30000"
    })

    assert has_element?(view, "#manifest-lumber td", "11")
    render_change(view, "market-good", %{"good" => "grain"})
    view |> element("#manifest-lumber button[phx-click=market-good]") |> render_click()
    assert has_element?(view, "#market-good", "Lumber")
    assert has_element?(view, "#manifest-lumber", "17.6 m³")
    assert has_element?(view, "#ship-capacity", "5500 / 500000 kg")
    assert has_element?(view, "#ship-capacity", "17.6 m³ / 900 m³")
    assert has_element?(view, "#manifest-lumber td", "$225")

    view
    |> element("button[phx-click=sort-manifest][phx-value-column=quantity]")
    |> render_click()

    assert has_element?(view, "th[aria-sort=ascending]", "Lots")

    view
    |> element("button[phx-click=sort-manifest][phx-value-column=quantity]")
    |> render_click()

    send(view.pid, {:game_changed, 0})
    assert has_element?(view, "th[aria-sort=descending]", "Lots")

    assert length(GameServer.snapshot(token, server).private["ships"][ship["id"]]["cargo"]) == 2
    advance(server, 2000)
    render_submit(view, "preview", %{"destination" => "Singapore"})
    assert render(view) =~ "Reserve fuel and sail"
    estimate = GameServer.preview(token, ship["id"], "Singapore", server)
    render_click(view, "sail")
    assert GameServer.snapshot(token, server).private["ships"][ship["id"]]["status"] == "sailing"

    render_click(view, "toggle-map-filters")
    assert has_element?(view, "#map-filters input[name=show_others][checked]")
    classes = Map.keys(GameServer.definitions().classes)

    for class <- classes do
      assert has_element?(view, "#map-filters input[type=checkbox][value='#{class}'][checked]")
    end

    render_change(view, "map-filters", %{"classes" => [], "show_others" => "true"})
    refute has_element?(view, "#world-map [data-map-ship]")
    refute has_element?(view, "#world-map [data-map-route]")
    render_change(view, "map-filters", %{"classes" => [ship["class"]], "show_others" => "false"})
    assert has_element?(view, "#world-map [data-map-ship='#{ship["id"]}']")
    send(view.pid, {:game_changed, 0})
    assert has_element?(view, "#map-filter-toggle[aria-expanded=true]")
    refute has_element?(view, "#map-filters input[name=show_others][checked]")
    render_click(view, "map-region", %{"id" => "Pearl River Delta"})
    assert has_element?(view, "#map-filters input[value='#{ship["class"]}'][checked]")
    render_click(view, "map-world")

    # A separate authenticated account has no ships of its own.
    {:ok, second_code} = GameServer.seed(server)

    other_conn =
      build_conn()
      |> get("/play")
      |> recycle()
      |> post("/session/redeem", %{"code" => second_code})

    assert Plug.Conn.get_session(other_conn, :account_token)
    {:ok, other_view, _} = live(recycle(other_conn), "/play")
    assert has_element?(other_view, "#world-map [data-map-ship='#{ship["id"]}']")
    render_click(other_view, "inspect-ship", %{"id" => ship["id"]})
    assert has_element?(other_view, "#map-ship-overlay", ship["name"])
    refute has_element?(other_view, "#map-ship-overlay", "Cargo aboard")
    refute has_element?(other_view, "#map-ship-overlay table")
    render_click(other_view, "close-map-ship")
    refute has_element?(other_view, "#map-ship-overlay")

    render_change(other_view, "map-filters", %{"classes" => classes, "show_others" => "false"})
    refute has_element?(other_view, "#world-map [data-map-ship]")
    refute has_element?(other_view, "#world-map [data-map-route]")
    render_change(other_view, "map-filters", %{"classes" => classes, "show_others" => "true"})
    assert has_element?(other_view, "#world-map [data-map-ship='#{ship["id"]}']")
    render_change(view, "map-filters", %{"classes" => classes, "show_others" => "true"})
    render_click(view, "toggle-map-filters")
    render_click(view, "ship", %{"id" => other_ship["id"]})

    view
    |> element("#world-map [phx-click=inspect-ship][phx-value-id='#{ship["id"]}']")
    |> render_click()

    assert has_element?(
             view,
             "button[phx-click=ship][phx-value-id='#{ship["id"]}'][aria-pressed=true]"
           )

    advance(server, estimate["duration_ms"] + 1000)

    render_change(view, "port", %{"id" => "Singapore"})
    view |> element("button[phx-click=port-market-side][phx-value-side=sell]") |> render_click()
    assert has_element?(view, "#port-market-table th", "Sell / demand")
    refute has_element?(view, "#port-market-table th", "Buy / supply")
    assert has_element?(view, "#trade-sell-lumber")
    refute has_element?(view, "#trade-buy-lumber")
    send(view.pid, {:game_changed, 0})
    assert has_element?(view, "button[phx-value-side=sell][aria-pressed=true]")

    render_submit(view, "trade", %{
      "action" => "sell",
      "good" => "lumber",
      "quantity" => "11",
      "limit" => "1"
    })

    render_change(view, "port", %{"id" => "Singapore"})
    refute has_element?(view, "td", "Appliances")
    after_sale = GameServer.snapshot(token, server)
    assert after_sale.private["ships"][ship["id"]]["cargo"] == []
    {:ok, spectator, _} = build_conn() |> live("/play")
    refute has_element?(spectator, "#cargo-ship-filter")
    render_click(spectator, "inspect-ship", %{"id" => ship["id"]})
    assert has_element?(spectator, "#public-ship-inspector", "Company: Browser Shipping")
    assert has_element?(spectator, "#public-ship-inspector", "Class: Balanced freighter")
    refute render(spectator) =~ "— Manifest"
    refute has_element?(spectator, "table[aria-label='Ship cargo manifest']")
    GenServer.stop(spectator.pid)
    GenServer.stop(view.pid)
    {:ok, reconnected, _} = conn |> recycle() |> live("/play")
    assert render(reconnected) =~ "Browser Shipping"
    refute render(reconnected) =~ token
  end

  test "perishable disclosures follow quantity, dispatch and underway time", %{
    server: server,
    code: code
  } do
    Application.put_env(:tijara_tides, :game_server, server)
    on_exit(fn -> Application.delete_env(:tijara_tides, :game_server) end)
    conn = build_conn() |> get("/play") |> recycle() |> post("/session/redeem", %{"code" => code})
    token = Plug.Conn.get_session(conn, :account_token)
    {:ok, view, _} = conn |> recycle() |> live("/play")

    view |> form("#company-form", %{"name" => "Cold Shipping"}) |> render_submit()
    view |> form("#loan-form", %{"amount" => "200000"}) |> render_submit()
    render_change(view, "port", %{"id" => "Jakarta"})

    for class <- ["reefer", "reefer", "freighter"],
        do: view |> form("#shipyard-" <> class) |> render_submit()

    render_change(view, "preview", %{"destination" => "Singapore"})
    assert has_element?(view, "#port-selector[data-selected='Jakarta']")
    assert has_element?(view, "#voyage-preview option[selected]", "Singapore")

    assert has_element?(
             view,
             "button[phx-click=port-market-side][phx-value-side=buy][aria-pressed=true]"
           )

    assert_push_event(view, "workspace-panel", %{panel: 0})
    view |> form("#trade-buy-fruit", %{"quantity" => "20"}) |> render_change()
    assert has_element?(view, "#trade-buy-fruit", "20 lots: first expiry")
    assert has_element?(view, "#trade-buy-fruit", "0.2 min handling")
    assert has_element?(view, "#trade-buy-fruit", "Estimates may change")
    view |> form("#trade-buy-fruit", %{"quantity" => "20"}) |> render_submit()
    advance(server, 11_000)
    view |> form("#voyage-preview", %{"destination" => "Singapore"}) |> render_change()
    assert has_element?(view, ".voyage-freshness", "Fruit: estimated time to first expiry")
    assert has_element?(view, ".voyage-freshness", "after unloading")
    render_click(view, "sail")
    before = GameServer.snapshot(token, server).private["voyage_freshness"]
    advance(server, 60_000)
    assert has_element?(view, ".voyage-freshness", "Fruit: estimated time to first expiry")
    # As the ship advances normally, the absolute arrival and unloading times stay
    # fixed; remaining freshness at those future instants is therefore unchanged.
    assert GameServer.snapshot(token, server).private["voyage_freshness"] == before
  end

  test "perishable lots split permanently and journal retries and failures stay atomic", %{
    server: server,
    code: code,
    world_id: world
  } do
    alias TijaraTides.Infrastructure.Persistence.FinancialLedger
    {:ok, %{"session" => token}} = GameServer.redeem(code, server)
    :ok = GameServer.connect(token, server)

    {:ok, _} =
      TijaraTides.CompanyFixture.command(
        token,
        "starter",
        %{
          "action" => "company",
          "name" => "Ledger company",
          "port" => "Jakarta",
          "package" => "fresh"
        },
        server
      )

    snapshot = GameServer.snapshot(token, server)
    ship = snapshot.private["ships"] |> Map.values() |> Enum.find(&(&1["class"] == "reefer"))

    [[parent]] =
      Repo.query!(
        "SELECT lot_id FROM game_cargo_holdings WHERE world_id=$1 AND market_id='Jakarta|fruit' ORDER BY position LIMIT 1",
        [world]
      ).rows

    buy = %{
      "action" => "buy",
      "destination" => "Singapore",
      "ship" => ship["id"],
      "good" => "fruit",
      "quantity" => 2,
      "limit" => 100_000
    }

    {:ok, result} = GameServer.command(token, "buy", buy, server)
    assert {:ok, ^result} = GameServer.command(token, "buy", buy, server)

    [[1]] =
      Repo.query!(
        "SELECT count(*) FROM game_journal_transactions WHERE world_id=$1 AND request_id='buy'",
        [world]
      ).rows

    assert [[500, 2]] ==
             Repo.query!(
               "SELECT sum(original_quantity_lots)::bigint,count(*) FROM game_cargo_lots WHERE world_id=$1 AND parent_lot_id=$2",
               [world, parent]
             ).rows

    assert [[0]] ==
             Repo.query!(
               "SELECT count(*) FROM game_cargo_holdings WHERE world_id=$1 AND lot_id=$2",
               [world, parent]
             ).rows

    [cargo] = GameServer.snapshot(token, server).private["ships"][ship["id"]]["cargo"]
    refute cargo["lot_id"] == parent

    assert [[parent]] ==
             Repo.query!(
               "SELECT parent_lot_id FROM game_cargo_lots WHERE world_id=$1 AND id=$2",
               [world, cargo["lot_id"]]
             ).rows

    assert :ok == FinancialLedger.audit(Repo, world)

    [[tx]] =
      Repo.query!(
        "SELECT id FROM game_journal_transactions WHERE world_id=$1 AND request_id='buy'",
        [world]
      ).rows

    assert_raise Postgrex.Error, fn ->
      Repo.query!("UPDATE game_journal_entries SET amount_cents=1 WHERE transaction_id=$1", [tx])
    end

    assert_raise Postgrex.Error, fn ->
      Repo.query!("DELETE FROM game_journal_transactions WHERE id=$1", [tx])
    end

    assert_raise Postgrex.Error, fn ->
      Repo.query!("INSERT INTO game_journal_entries VALUES($1,99,'capital',1)", [tx])
    end

    assert_raise Postgrex.Error, fn ->
      Repo.query!(
        "SELECT post_game_journal($1,$2,'bad',0,0,NULL,NULL,NULL,ARRAY['cash_available','capital'],ARRAY[10,-9]::bigint[])",
        [world, ship["company_id"]]
      )
    end

    assert :ok == FinancialLedger.audit(Repo, world)

    advance(server, 2000)
    {:ok, before} = GameStore.claim(Repo, world)

    other =
      before.entities["ships"]
      |> Map.values()
      |> Enum.find(&(&1["company_id"] == ship["company_id"] and &1["id"] != ship["id"]))

    moved =
      before
      |> put_in([:entities, "ships", ship["id"], "cargo"], [])
      |> put_in([:entities, "ships", other["id"], "cargo"], [cargo])

    assert {:ok, :ok} = GameStore.commit(Repo, world, before.epoch, before, moved)

    assert [[other["id"]]] ==
             Repo.query!(
               "SELECT ship_id FROM game_cargo_holdings WHERE world_id=$1 AND lot_id=$2",
               [world, cargo["lot_id"]]
             ).rows

    before = moved

    account =
      Game.get(before, "accounts", snapshot.private["account"]["id"])

    {:ok, changed, _} =
      Game.execute(before, account, buy, %{}, TijaraTides.Infrastructure.GameCatalogue.all())

    [[lot_count]] =
      Repo.query!("SELECT count(*) FROM game_cargo_lots WHERE world_id=$1", [world]).rows

    [[journal_count]] =
      Repo.query!("SELECT count(*) FROM game_journal_transactions WHERE world_id=$1", [world]).rows

    assert_raise Postgrex.Error, fn ->
      GameStore.commit(
        Repo,
        world,
        before.epoch,
        before,
        changed,
        {account["id"], "rollback", nil, %{}}
      )
    end

    assert [[lot_count]] ==
             Repo.query!("SELECT count(*) FROM game_cargo_lots WHERE world_id=$1", [world]).rows

    assert [[journal_count]] ==
             Repo.query!("SELECT count(*) FROM game_journal_transactions WHERE world_id=$1", [
               world
             ]).rows

    assert :ok == FinancialLedger.audit(Repo, world)
    {:ok, restored} = GameStore.claim(Repo, world)
    assert restored.entities == before.entities
    assert restored.next_lot_id == before.next_lot_id

    assert_raise Postgrex.Error, fn ->
      Repo.query!("UPDATE game_ledger_balances SET balance_cents=0 WHERE world_id=$1", [world])
    end

    assert_raise Postgrex.Error, fn ->
      Repo.query!(
        "UPDATE game_cargo_lots SET original_quantity_lots=1 WHERE world_id=$1 AND id=$2",
        [world, cargo["lot_id"]]
      )
    end

    unsupported =
      update_in(restored, [:entities, "companies", ship["company_id"], "cash"], &(&1 + 100))

    assert_raise ArgumentError, fn ->
      GameStore.commit(Repo, world, restored.epoch, restored, unsupported)
    end

    assert :ok == FinancialLedger.audit(Repo, world)

    # A partial sale creates a consumed child and an owned remainder, and posts COGS.
    at_port = put_in(restored, [:entities, "ships", other["id"], "port"], "Singapore")

    sell = %{
      "action" => "sell",
      "ship" => other["id"],
      "good" => "fruit",
      "quantity" => 1,
      "limit" => 1
    }

    {:ok, sold, _} =
      Game.execute(at_port, account, sell, %{}, TijaraTides.Infrastructure.GameCatalogue.all())

    assert {:ok, :ok} = GameStore.commit(Repo, world, restored.epoch, restored, sold)
    [remainder] = sold.entities["ships"][other["id"]]["cargo"]
    assert remainder["quantity"] == 1
    refute remainder["lot_id"] == cargo["lot_id"]

    assert [[2, 2]] ==
             Repo.query!(
               "SELECT sum(original_quantity_lots)::bigint,count(*) FROM game_cargo_lots WHERE world_id=$1 AND parent_lot_id=$2",
               [world, cargo["lot_id"]]
             ).rows

    assert :ok == FinancialLedger.audit(Repo, world)
  end

  defp advance(server, ms) do
    :sys.replace_state(server, fn state -> %{state | last_mono: state.last_mono - ms} end)
    send(server, :tick)
    GameServer.snapshot(nil, server)
  end

  test "email identity survives storage reload and HTTP confirmation consumes links only on POST",
       c do
    assert {:error, :email_invalid} =
             GameServer.email_request(nil, "login", %{}, "x", "browser", c.server)

    assert {:error, :email_link_invalid} = GameServer.email_redeem(nil, nil, nil, c.server)
    Application.put_env(:tijara_tides, :game_server, c.server)
    on_exit(fn -> Application.delete_env(:tijara_tides, :game_server) end)

    conn =
      build_conn() |> get("/play") |> recycle() |> post("/session/redeem", %{"code" => c.code})

    token = Plug.Conn.get_session(conn, :account_token)

    assert {:ok, %{"requested" => true}} =
             GameServer.email_request(
               token,
               "link",
               "owner@example.com",
               "request",
               "browser",
               c.server
             )

    [row] = GameServer.email_pending(c.server)
    {:ok, disabled_email_view, html} = conn |> recycle() |> live("/play")
    assert html =~ "Email linking is not available on this server yet."
    refute html =~ "Link an email to sign in on another device."
    refute has_element?(disabled_email_view, "#email-link-form")

    old_mailer = Application.get_env(:tijara_tides, TijaraTides.Infrastructure.Mailer)
    Application.put_env(:tijara_tides, :email_enabled, true)
    Application.put_env(:tijara_tides, :email_base_url, "https://game.example.com")
    Application.put_env(:tijara_tides, :email_from, "game@example.com")

    Application.put_env(:tijara_tides, TijaraTides.Infrastructure.Mailer,
      adapter: Swoosh.Adapters.Test
    )

    Application.put_env(:swoosh, :shared_test_process, self())

    on_exit(fn ->
      Application.put_env(:tijara_tides, :email_enabled, false)
      Application.put_env(:tijara_tides, TijaraTides.Infrastructure.Mailer, old_mailer)
      Application.delete_env(:tijara_tides, :email_base_url)
      Application.delete_env(:tijara_tides, :email_from)
      Application.delete_env(:swoosh, :shared_test_process)
    end)

    assert {:noreply, nil} = TijaraTides.Infrastructure.EmailDelivery.handle_info(:poll, nil)
    assert_receive {:email, message}
    assert message.to == [{"", "owner@example.com"}]
    assert message.text_body =~ "https://game.example.com/email/verify?token="
    assert GameServer.email_pending(c.server) == []
    {:ok, view, _} = conn |> recycle() |> live("/play")
    assert has_element?(view, "#email-link-form")
    refute has_element?(view, "#invitations")
    refute has_element?(view, "#email-invite-form")
    link = GameServer.email_token(row["id"])
    prepared = conn |> recycle() |> get("/email/verify", %{"token" => link})
    assert redirected_to(prepared) == "/email/confirm"
    assert Plug.Conn.get_resp_header(prepared, "referrer-policy") == ["no-referrer"]
    assert GameServer.snapshot(token, c.server).private["account"]["email"] == nil
    confirmed = prepared |> recycle() |> post("/email/redeem")
    assert redirected_to(confirmed) == "/play"
    session = Plug.Conn.get_session(confirmed, :account_token)
    # Simulate losing the POST response and re-opening the emailed URL using
    # the cookie issued before the commit.
    reopened = prepared |> recycle() |> get("/email/verify", %{"token" => link})
    recovered = reopened |> recycle() |> post("/email/redeem")
    assert Plug.Conn.get_session(recovered, :account_token) == session

    snapshot = GameServer.snapshot(session, c.server)
    assert snapshot.private["account"]["email"] == "owner@example.com"
    {:ok, linked_view, _} = confirmed |> recycle() |> live("/play")
    assert has_element?(linked_view, ".company-menu-dismiss #verified-email")
    refute has_element?(linked_view, "#email-verification")
    refute has_element?(linked_view, "#email-link-form")
    assert has_element?(linked_view, "#invitations")
    refute has_element?(linked_view, "#email-identity")
    assert has_element?(linked_view, "#email-invite-form")

    assert GameServer.email_pending(c.server) == []

    assert %{rows: [["owner@example.com"]]} =
             Repo.query!("SELECT email FROM game_accounts WHERE world_id=$1", [c.world_id])

    assert {:ok, _} =
             GameServer.email_request(
               session,
               "invite",
               "invitee@example.com",
               "invitation",
               "browser",
               c.server
             )

    [invite] = GameServer.email_pending(c.server)

    assert {:ok, _} =
             GameServer.email_redeem(
               GameServer.email_token(invite["id"]),
               GameServer.token(),
               nil,
               c.server
             )

    assert %{rows: [[2]]} =
             Repo.query!(
               "SELECT count(*) FROM game_accounts WHERE world_id=$1 AND email IS NOT NULL",
               [c.world_id]
             )

    replacement =
      start_supervised!(
        {GameServer, name: nil, enabled: true, world_id: c.world_id, tick_ms: 86_400_000},
        id: :email_replacement
      )

    assert GameServer.snapshot(session, replacement).private["account"]["email"] ==
             "owner@example.com"
  end

  test "login throttling separates clients behind Render and still limits each requester", c do
    Application.put_env(:tijara_tides, :game_server, c.server)
    Application.put_env(:tijara_tides, :email_enabled, true)
    Application.put_env(:tijara_tides, :render_proxy, true)

    on_exit(fn ->
      Application.delete_env(:tijara_tides, :game_server)
      Application.put_env(:tijara_tides, :email_enabled, false)
      Application.delete_env(:tijara_tides, :render_proxy)
    end)

    request = fn ip, n ->
      conn =
        %{build_conn() | remote_ip: {10, 0, 0, 1}}
        |> Plug.Conn.put_req_header("x-forwarded-for", "1.1.1.1, #{ip}, 172.64.1.2, 10.0.0.2")

      post(conn, "/email/request", %{"email" => "login#{n}@example.com", "request_id" => "#{n}"})
    end

    for n <- 1..11, do: request.("8.8.8.8", n)
    request.("9.9.9.9", 12)

    rows =
      Repo.query!(
        "SELECT requester,count(*) FROM game_email_requests WHERE world_id=$1 GROUP BY requester",
        [c.world_id]
      ).rows

    assert Enum.sort(rows) ==
             Enum.sort([[GameServer.hash("8.8.8.8"), 10], [GameServer.hash("9.9.9.9"), 1]])
  end
end
