defmodule TijaraTides.Domain.AccountQuotaPropertiesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias TijaraTides.Domain.Account

  property "quota consumption and invitation issue enforce independent suspension and capacity limits" do
    check all(
            quota <- integer(-2..5),
            suspended <- boolean(),
            outstanding <- integer(0..4),
            max_runs: 50,
            max_shrinking_steps: 100
          ) do
      account = %{
        Account.new("owner", nil, false, 0)
        | invite_quota: quota,
          suspended_ms: if(suspended, do: 0)
      }

      eligible = quota > 0 and not suspended

      if eligible do
        assert Account.consume_invitation(account) == %{account | invite_quota: quota - 1}
      else
        assert_raise ArgumentError, fn -> Account.consume_invitation(account) end
      end

      if eligible and outstanding < 3 do
        assert Account.issue_invitation(account, outstanding) ==
                 {:ok, %{account | invite_quota: quota - 1}}
      else
        assert Account.issue_invitation(account, outstanding) == {:error, :no_invitation_quota}
      end
    end
  end

  property "earning invitations accepts only positive whole counts" do
    check all(
            quota <- integer(0..5),
            count <- integer(-5..5),
            max_runs: 50,
            max_shrinking_steps: 100
          ) do
      account = %{Account.new("owner", nil, false, 0) | invite_quota: quota}

      if count > 0 do
        assert Account.earn_invitations(account, count).invite_quota == quota + count
      else
        assert_raise FunctionClauseError, fn -> Account.earn_invitations(account, count) end
      end
    end
  end

  test "earning refuses fractional counts even when positive" do
    account = Account.new("owner", nil, false, 0)

    for count <- [0, -1, 0.5, 1.5, nil, "1"] do
      assert_raise FunctionClauseError, fn -> Account.earn_invitations(account, count) end
    end
  end

  test "zero-quota invitee rejects an invitation before trying to consume it" do
    fixture =
      Jason.decode!(
        File.read!("test/fixtures/property_regressions/command_fuzzer/account-zero-quota.json")
      )

    account = %{Account.new("invitee", "sponsor", false, 0) | invite_quota: fixture["quota"]}

    assert {:error, :no_invitation_quota} =
             Account.issue_invitation(account, fixture["outstanding"])

    assert_raise ArgumentError, fn -> Account.consume_invitation(account) end
  end

  test "suspension and quota type guards hold even on direct aggregate consumption" do
    account = Account.new("owner", nil, true, 0)
    assert_raise ArgumentError, fn -> Account.consume_invitation(%{account | suspended_ms: 0}) end

    for quota <- [nil, false, "3", 1.5, [], %{}] do
      assert_raise ArgumentError, fn ->
        Account.consume_invitation(%{account | invite_quota: quota})
      end
    end
  end
end
