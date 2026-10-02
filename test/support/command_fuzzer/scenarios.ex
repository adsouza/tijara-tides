defmodule TijaraTides.CommandFuzzer.Scenarios do
  @moduledoc "Symbolic scenario skeletons. Essential transitions are never shrunk away."
  alias TijaraTides.Domain.{Game, ReadState, CompanyFinanceWorld}

  defp put_row(game, table, id, row) do
    before = ReadState.get(game, table, id)

    game
    |> Map.update!(
      :entities,
      &Map.update(&1, table, %{id => row}, fn rows -> Map.put(rows, id, row) end)
    )
    |> TijaraTides.Domain.EntityIndex.update(table, id, before, row)
    |> TijaraTides.Domain.ChangeSet.record(table, id, :put)
  end

  def families, do: [:finance, :berths, :route, :liquidation]

  def fixture(game, catalogue, bindings, family) do
    # Ordinary invitation, redemption and capitalization establish a second owner.
    a = ReadState.get(game, "accounts", bindings.a)

    {:ok, game, _} =
      Game.execute(
        game,
        a,
        %{"action" => "invite"},
        %{id: "second-invite", invite_hash: "second-invite", catalogue: catalogue},
        catalogue
      )

    {:ok, game, _} =
      Game.redeem(game, "second-invite", bindings.b_session, %{id: "secondary", wall_ms: 1})

    {:ok, game, _} =
      TijaraTides.CompanyFixture.create_company(
        game,
        ReadState.get(game, "accounts", "secondary"),
        "Second owner",
        "Jakarta",
        "general",
        %{id: "secondary-company", catalogue: catalogue}
      )

    bindings =
      Map.merge(bindings, %{
        b: "secondary",
        company_b: "secondary-company",
        b_ship: "secondary-company:1"
      })

    # Existing protected cash on the second owner remains outside the exploration prefix.
    {:ok, game, _} =
      Game.execute(
        game,
        ReadState.get(game, "accounts", bindings.b),
        %{"action" => "borrow", "amount" => 10_000},
        %{id: "fixture-loan"},
        catalogue
      )

    {:ok, game, _} =
      Game.execute(
        game,
        ReadState.get(game, "accounts", bindings.b),
        %{"action" => "recast", "loan" => "fixture-loan", "amount" => 1000},
        %{},
        catalogue
      )

    {:ok, game, _} =
      Game.execute(
        game,
        ReadState.get(game, "accounts", bindings.b),
        %{
          "action" => "instruction",
          "ship" => bindings.b_ship,
          "port" => "Singapore",
          "side" => "buy",
          "good" => "lumber",
          "quantity" => 1,
          "limit" => 1,
          "budget" => 100,
          "onward" => "Jakarta"
        },
        %{id: "protected-instruction"},
        catalogue
      )

    {:ok, game, _} =
      Game.execute(
        game,
        ReadState.get(game, "accounts", bindings.b),
        %{
          "action" => "visit_budget",
          "ship" => bindings.b_ship,
          "port" => "Singapore",
          "amount" => 100
        },
        %{},
        catalogue
      )

    catalogue =
      catalogue
      |> Map.put("weather", %{"chance_bps" => 0})
      |> Map.put("auctions", %{"interval_ms" => 10_000, "window_ms" => 10_000})
      |> put_in(["ports", "Jakarta", "berth_count"], 1)

    {game, bindings} = specialize(game, bindings, family, catalogue)
    {game, catalogue, bindings}
  end

  defp specialize(game, b, :finance, _catalogue) do
    # Supported historical state: a suspended invitee with five closed, zero-balance
    # companies. Each row has its actual company/account FK, and cooldowns have elapsed.
    account = ReadState.get(game, "accounts", b.b)
    # Use the other active company as an unrelated owner; the historical beneficiary
    # is a third account so existing balances, protected cash and loans remain valid.
    beneficiary = %{
      account
      | "id" => "beneficiary",
        "company_id" => nil,
        "inviter" => b.a,
        "suspended_ms" => 0,
        "bankruptcies" => 5
    }

    game =
      game
      |> put_row("accounts", "beneficiary", beneficiary)
      |> put_row("sessions", b.beneficiary_session, %{
        "account_id" => "beneficiary",
        "expires_at" => 365 * 86_400_000
      })

    template = ReadState.get(game, "companies", b.company_b)

    game =
      Enum.reduce(1..5, game, fn n, game ->
        id = "history:#{n}"

        row = %{
          template
          | "id" => id,
            "account_id" => "beneficiary",
            "name" => "History #{n}",
            "cash" => 0,
            "reserved" => 0,
            "unpaid" => 0,
            "profit" => 0,
            "bankruptcy_ms" => 0
        }

        game
        |> CompanyFinanceWorld.open(row)
        |> put_row("bankruptcy_events", id, %{
          "id" => id,
          "company_id" => id,
          "account_id" => "beneficiary",
          "created_ms" => 0,
          "restart_ms" => 0,
          "reason" => "forced",
          "guarantee_id" => nil,
          "guaranteed_debt" => 0
        })
      end)

    {game, Map.put(b, :beneficiary, "beneficiary")}
  end

  defp specialize(game, b, :liquidation, catalogue) do
    # An established debtor with cash below principal after an ordinary asset purchase.
    {:ok, game, _} =
      Game.execute(
        game,
        ReadState.get(game, "accounts", b.a),
        %{"action" => "borrow", "amount" => 8_000_000},
        %{id: "estate-loan"},
        catalogue
      )

    {:ok, game, _} =
      Game.execute(
        game,
        ReadState.get(game, "accounts", b.a),
        %{
          "action" => "purchase_ship",
          "class" => "tanker",
          "port" => "Jakarta",
          "price_limit" => 5_000_000
        },
        %{id: "estate-hull-a"},
        catalogue
      )

    {:ok, game, _} =
      Game.execute(
        game,
        ReadState.get(game, "accounts", b.a),
        %{
          "action" => "purchase_ship",
          "class" => "tanker",
          "port" => "Jakarta",
          "price_limit" => 5_000_000
        },
        %{id: "estate-hull-b"},
        catalogue
      )

    {game, b}
  end

  defp specialize(game, b, _, _), do: {game, b}

  def command(spec, params \\ %{}, opts \\ []),
    do: %{
      op: :command,
      spec: spec,
      params: params,
      actor: Keyword.get(opts, :actor, :a),
      as: Keyword.get(opts, :as),
      expected: Keyword.get(opts, :error, :ok)
    }

  def tick(target, invariant \\ nil), do: %{op: :tick, target: target, invariant: invariant}

  def prefix(:finance, p) do
    [
      command(:guarantee, %{"amount" => 5_000_000}, as: :guarantee),
      command(:company, %{"name" => "Restart"}, actor: :beneficiary, as: :restart_company),
      command(:borrow, %{"amount" => 5_000_000}, actor: :beneficiary, as: :loan),
      command(:recast, %{"amount" => 1_000_000}, actor: :beneficiary)
    ] ++
      if(p.mode == 0,
        do: [command(:repay, %{}, actor: :beneficiary), tick(0, :guarantee_release)],
        else: [
          command(
            :purchase_ship,
            %{"class" => "freighter", "port" => "Jakarta", "price_limit" => 4_000_000},
            actor: :beneficiary,
            as: :asset
          ),
          command(:bankruptcy, %{}, actor: :beneficiary),
          tick(0, :guarantee_claim)
        ]
      )
  end

  def prefix(:berths, p) do
    [
      command(:buy, %{"quantity" => p.quantity}, as: :first_purchase),
      command(:queued_buy, %{"quantity" => p.quantity}),
      command(:queued_buy, %{"quantity" => p.quantity}, error: :berth_order_pending),
      command(:cancel_berth_trade),
      command(:queued_buy, %{"quantity" => p.quantity}),
      tick(60_000, :queue_progress),
      command(:sail, %{"destination" => "Singapore", "fuel_limit" => 100_000_000}),
      tick({:fraction, :ship, 2}),
      command(:reroute, %{"destination" => "Jakarta", "fuel_limit" => 100_000_000}),
      tick({:arrival, :ship}, :return_port)
    ]
  end

  def prefix(:route, p) do
    [
      command(:add_stop, %{"port" => "Jakarta"}, as: :origin),
      command(:add_stop, %{"port" => "Singapore"}, as: :destination),
      command(:visit_budget_origin, %{"amount" => p.amount}),
      command(:visit_budget_destination, %{"amount" => 2 * p.amount}),
      command(:add_rule, %{"quantity" => p.quantity, "limit" => 1}, as: :rule),
      command(:start),
      command(:sail, %{"destination" => "Singapore", "fuel_limit" => 0},
        error: :departure_fuel_limit
      ),
      command(:sail, %{"destination" => "Singapore", "fuel_limit" => 100_000_000}),
      tick({:arrival, :ship}),
      command(:sail, %{"destination" => "Jakarta", "fuel_limit" => 100_000_000}),
      tick({:arrival, :ship}, :return_visit)
    ]
  end

  def prefix(:liquidation, p) do
    [
      command(:rename_ship, %{"name" => "Estate carrier"}),
      command(:warehouse_lease, %{"blocks" => 1, "days" => 1, "price" => 100}, as: :warehouse),
      command(:buy, %{"quantity" => p.quantity}),
      tick(60_000),
      command(:warehouse_store, %{"quantity" => p.quantity}),
      tick(60_000),
      tick({:lease_expiry, -1}),
      tick(1, :before_grace),
      command(:bankruptcy),
      tick({:grace_end, 0}, :liquidating),
      tick({:auction_close, 1}, :liquidation_complete)
    ]
  end

  def milestones(:finance), do: [:partial_payment, :escrow_acquired, :escrow_settled]

  def milestones(:berths),
    do: [:queued, :cancelled_queue, :queue_progress, :rerouted, :return_port]

  def milestones(:route), do: [:budget_acquired, :budget_released, :return_visit]
  def milestones(:liquidation), do: [:stored, :grace, :liquidating, :liquidation_complete]
end
