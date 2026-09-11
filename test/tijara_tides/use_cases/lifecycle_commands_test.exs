defmodule TijaraTides.UseCases.LifecycleCommandsTest do
  use ExUnit.Case, async: true
  alias TijaraTides.UseCases.LifecycleCommands

  defmodule Store do
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
end
