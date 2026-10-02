defmodule TijaraTides.UseCases.LifecycleCommandsTest do
  use ExUnit.Case, async: true
  alias TijaraTides.UseCases.LifecycleCommands

  defmodule Store do
    def allocate_lot_ids(_, count),
      do: Enum.map(1..count, fn _ -> "test-lot:#{System.unique_integer([:positive])}" end)

    def commit(callback, before, changed, receipt), do: callback.(before, changed, receipt)
    def restore(_callback, game, _operation), do: game
  end

  defp game, do: %{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}

  test "lifecycle writes use the same prepared atomic acceptance as player commands" do
    store =
      {Store,
       fn before, changed, receipt ->
         assert before == game()
         assert changed.revision == 1
         assert receipt == nil
         assert changed.entities["invitations"]["code"]["status"] == "issued"
         assert :ok == TijaraTides.Domain.ChangeSet.assert_complete!(before, changed)
         {:ok, :ok}
       end}

    assert {:ok, outcome} = LifecycleCommands.run(game(), {:seed, "code"}, %{}, store)
    assert outcome.committed?
    assert outcome.game.changes == %{}
  end

  test "failed lifecycle persistence returns no accepted world" do
    store = {Store, fn _, _, _ -> {:error, :ownership_lost} end}
    assert {:halt, :ownership_lost} == LifecycleCommands.run(game(), {:seed, "code"}, %{}, store)
  end

  test "missing delivery and existing email request replay without a commit" do
    store = {Store, fn _, _, _ -> flunk("replay must not commit") end}

    assert {:ok, %{committed?: false}} =
             LifecycleCommands.run(game(), {:email_delivered, "missing"}, %{}, store)

    game = %{game() | entities: %{"email_requests" => %{"r" => %{}}}}

    assert {:ok, %{committed?: false, reply: %{"requested" => true}}} =
             LifecycleCommands.run(
               game,
               {:email_request, nil, "login", "ignored"},
               %{id: "r"},
               store
             )
  end

  defp absent_company do
    alias TijaraTides.Domain.{Game, State}

    catalogue =
      TijaraTides.Infrastructure.GameCatalogue.all()
      |> Map.put("dormancy", %{"absence_ms" => 100, "warning_ms" => 200})

    state = Game.initialize(game(), catalogue)
    {:ok, state, _} = Game.seed_invite(state, "invite")
    {:ok, state, _} = Game.redeem(state, "invite", "session", %{id: "owner", wall_ms: 0})

    {:ok, state, _} =
      Game.execute(
        state,
        State.get(state, "accounts", "owner"),
        %{"action" => "company", "name" => "Away"},
        %{id: "company", catalogue: catalogue},
        catalogue
      )

    state = TijaraTides.Domain.Services.Bankruptcy.advance_dormancy(state, 0, catalogue)
    {state, catalogue}
  end

  test "return before deadline clears warnings, return at deadline commits closure first" do
    alias TijaraTides.Domain.{AccountWorld, State}
    {game, catalogue} = absent_company()
    warned = TijaraTides.Domain.Services.Bankruptcy.advance_dormancy(game, 100, catalogue)

    store =
      {Store,
       fn before, changed, _ ->
         assert before.clock_ms == changed.clock_ms
         assert :ok == TijaraTides.Domain.ChangeSet.assert_complete!(before, changed)
         {:ok, :ok}
       end}

    assert {:ok, outcome} =
             LifecycleCommands.run(
               warned,
               {:visit, "session"},
               %{wall_ms: 299, catalogue: catalogue},
               store
             )

    assert State.get(outcome.game, "company_dormancy", "company")["closes_ms"] == nil
    assert State.get(outcome.game, "accounts", "owner")["company_id"] == "company"

    assert {:ok, outcome} =
             LifecycleCommands.run(
               warned,
               {:visit, "session"},
               %{wall_ms: 300, catalogue: catalogue},
               store
             )

    assert State.get(outcome.game, "accounts", "owner")["company_id"] == nil
    assert State.get(outcome.game, "company_dormancy", "company")["closed_ms"] == 300
  end

  test "wall timer persists warnings while the world clock is stopped and cannot publish a rejected closure" do
    alias TijaraTides.Domain.State
    {game, catalogue} = absent_company()
    store = {Store, fn _, _, _ -> {:ok, :ok} end}

    assert {:ok, warning} =
             LifecycleCommands.run(
               game,
               :dormancy_check,
               %{wall_ms: 100, catalogue: catalogue},
               store
             )

    assert warning.committed?
    assert warning.game.clock_ms == 0
    assert State.get(warning.game, "company_dormancy", "company")["closes_ms"] == 300

    assert {:halt, :ownership_lost} =
             LifecycleCommands.run(
               warning.game,
               :dormancy_check,
               %{wall_ms: 300, catalogue: catalogue},
               {Store, fn _, _, _ -> {:error, :ownership_lost} end}
             )

    assert State.get(warning.game, "accounts", "owner")["company_id"] == "company"

    assert {:error, :invalid_session} =
             LifecycleCommands.run(
               warning.game,
               {:visit, "bad"},
               %{wall_ms: 300, catalogue: catalogue},
               {Store, fn _, _, _ -> flunk("invalid visit must not commit") end}
             )
  end
end
