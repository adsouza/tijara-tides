defmodule TijaraTides.Domain.IdentityHistoryTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{Account, EntityIndex, ReadState}

  test "compaction retains quota work, delivery work, rate window and ten visible requests" do
    now = 10_000_000

    requests =
      Map.new(1..12, fn n ->
        id = "r#{n}"

        {id,
         %{
           "id" => id,
           "account_id" => "a",
           "purpose" => "link",
           "created_ms" => n,
           "delivery" => "sent",
           "used_session" => nil,
           "expires_ms" => 100
         }}
      end)

    requests =
      requests
      |> Map.put("pending", %{
        "id" => "pending",
        "account_id" => "a",
        "purpose" => "invite",
        "created_ms" => 0,
        "delivery" => "pending",
        "used_session" => nil,
        "expires_ms" => 100
      })
      |> Map.put("rate", %{
        "id" => "rate",
        "purpose" => "login",
        "created_ms" => now - 3_599_999,
        "delivery" => "ignored",
        "used_session" => nil,
        "expires_ms" => 0
      })
      |> Map.put("boundary", %{
        "id" => "boundary",
        "purpose" => "login",
        "created_ms" => now - 3_600_000,
        "delivery" => "ignored",
        "used_session" => nil,
        "expires_ms" => 0
      })

    game =
      %{
        clock_ms: 50,
        entities: %{
          "email_requests" => requests,
          "sessions" => %{
            "expired" => %{"expires_at" => now},
            "live" => %{"expires_at" => now + 1}
          },
          "invitations" => %{
            "quota" => %{"status" => "issued", "expires_ms" => 0},
            "done" => %{"status" => "redeemed"}
          }
        }
      }
      |> EntityIndex.rebuild()

    compact = Account.compact_history(game, now)
    assert Map.keys(compact.entities["sessions"]) == ["live"]
    assert Map.keys(compact.entities["invitations"]) == ["quota"]
    assert map_size(compact.entities["email_requests"]) == 12
    assert ReadState.get(compact, "email_requests", "pending")
    assert ReadState.get(compact, "email_requests", "rate")
    refute ReadState.get(compact, "email_requests", "r1")
    refute ReadState.get(compact, "email_requests", "r2")
    refute ReadState.get(compact, "email_requests", "boundary")
    assert length(ReadState.owned(compact, "email_requests", "account_id", "a")) == 11
    assert ReadState.owned(compact, "email_requests", "account_id", nil) == [requests["rate"]]
    restored = Account.restore_history(compact, "email_requests", "r1", requests["r1"])
    assert length(ReadState.owned(restored, "email_requests", "account_id", "a")) == 12
    assert Map.get(restored, :changes, %{}) == %{}
  end
end
