defmodule TijaraTides.UseCases.OperatorCommandsTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.Account
  alias TijaraTides.Domain.Account.Rows
  alias TijaraTides.UseCases.OperatorCommands

  defmodule Store do
    def receipt(callback, owner, request, fingerprint),
      do: callback.({:receipt, owner, request, fingerprint})

    def commit(callback, before, changed, receipt),
      do: callback.({:commit, before, changed, receipt})
  end

  defp game do
    account = %{Account.new("a", "sponsor", false, 0) | email: "player@example.com"}

    %{
      clock_ms: 0,
      epoch: 1,
      revision: 0,
      entities: %{"accounts" => %{"a" => Rows.encode(account)}}
    }
  end

  test "normalized email resolves a verified account and commits an isolated operator receipt" do
    store =
      {Store,
       fn
         {:receipt, "operator:grant_invitations", "grant-1", fingerprint} ->
           assert byte_size(fingerprint) == 64
           :new

         {:commit, before, changed, {"operator:grant_invitations", "grant-1", _, result}} ->
           assert changed.entities["accounts"]["a"]["invite_quota"] == 2
           assert changed.revision == 1
           assert result["account_id"] == "a"
           assert result["quota_before"] == 0
           assert :ok == TijaraTides.Domain.ChangeSet.assert_complete!(before, changed)
           {:ok, :ok}
       end}

    assert {:ok, %{committed?: true}} =
             OperatorCommands.grant_invitations(
               game(),
               {:email, " Player@Example.com "},
               2,
               "grant-1",
               %{wall_ms: 0},
               store
             )
  end

  test "durable replay is checked before missing targets and capacity" do
    result = %{"granted" => 2, "quota_after" => 2}
    store = {Store, fn {:receipt, _, "replay", _} -> {:replay, result} end}

    assert {:ok, %{committed?: false, reply: ^result}} =
             OperatorCommands.grant_invitations(
               game(),
               {:account, "gone"},
               2,
               "replay",
               %{wall_ms: 0},
               store
             )
  end

  test "invalid arguments never touch storage; absent and ambiguous identities do not commit" do
    store = {Store, fn _ -> flunk("invalid arguments must not access storage") end}

    for request <- [nil, "", String.duplicate("x", 129), "line\nbreak", <<255>>] do
      assert {:error, :invalid_request_id} =
               OperatorCommands.grant_invitations(
                 game(),
                 {:account, "a"},
                 1,
                 request,
                 %{wall_ms: 0},
                 store
               )
    end

    for count <- [0, -1, 4, "2", 1.0] do
      assert {:error, :invalid_invitation_count} =
               OperatorCommands.grant_invitations(
                 game(),
                 {:account, "a"},
                 count,
                 "request",
                 %{wall_ms: 0},
                 store
               )
    end

    assert {:error, :email_invalid} = OperatorCommands.validate({:email, "broken"}, 1, "request")
    assert {:error, :invalid_account_selector} = OperatorCommands.validate("a", 1, "request")
    assert {:error, :invalid_account_id} = OperatorCommands.validate({:account, ""}, 1, "request")

    store = {Store, fn {:receipt, _, _, _} -> :new end}

    assert {:error, :account_not_found} =
             OperatorCommands.grant_invitations(
               game(),
               {:email, "absent@example.com"},
               1,
               "request",
               %{wall_ms: 0},
               store
             )

    duplicate = Map.put(game().entities["accounts"]["a"], "id", "b")
    ambiguous = put_in(game().entities["accounts"]["b"], duplicate)

    assert {:error, :ambiguous_account} =
             OperatorCommands.grant_invitations(
               ambiguous,
               {:email, "player@example.com"},
               1,
               "request",
               %{wall_ms: 0},
               store
             )
  end

  test "failed persistence never accepts a candidate or reports success" do
    store =
      {Store,
       fn
         {:receipt, _, _, _} -> :new
         {:commit, _, _, _} -> {:error, :ownership_lost}
       end}

    assert {:halt, :ownership_lost} =
             OperatorCommands.grant_invitations(
               game(),
               {:account, "a"},
               1,
               "request",
               %{wall_ms: 0},
               store
             )
  end
end
