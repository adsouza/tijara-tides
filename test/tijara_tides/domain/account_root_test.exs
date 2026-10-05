defmodule TijaraTides.Domain.AccountRootTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.Account
  alias Account.{BankruptcyEvent, Rows}

  test "operator grants accept exact remaining capacity and refuse one more" do
    for quota <- 0..3, outstanding <- 0..(3 - quota), count <- 1..3 do
      account = %{Account.new("a", "sponsor", false, 0) | invite_quota: quota}

      if quota + outstanding + count <= 3 do
        assert {:ok, %{invite_quota: next}} =
                 Account.grant_invitations(account, count, outstanding)

        assert next == quota + count
      else
        assert {:error, :invitation_capacity} =
                 Account.grant_invitations(account, count, outstanding)
      end
    end

    account = Account.new("a", "sponsor", false, 0)

    for invalid <- [0, -1, 4, 1.0, "1", nil] do
      assert {:error, :invalid_invitation_count} = Account.grant_invitations(account, invalid, 0)
    end

    assert {:error, :account_suspended} =
             Account.grant_invitations(%{account | suspended_ms: 0}, 1, 0)
  end

  test "quota changes preserve typed account state and enforce outstanding limits" do
    account = Account.new("a", "sponsor", true, 0)
    assert {:error, :no_invitation_quota} = Account.issue_invitation(account, 3)
    {:ok, next} = Account.issue_invitation(account, 2)
    assert next.invite_quota == 2
    assert Account.restore_invitation(next) == account

    assert {:error, :no_invitation_quota} =
             Account.issue_invitation(%{account | suspended_ms: 0}, 0)

    assert Rows.decode(Rows.encode(account)) == account
  end

  test "company closure updates history, suspends at five, and cannot repeat" do
    account = Account.new("a", "sponsor", true, 0)

    closed =
      Enum.reduce(1..5, account, fn n, acc ->
        id = "company:#{n}"
        attached = Account.attach_company(acc, id, true, n * 200, 100)

        event = %BankruptcyEvent{
          id: id,
          company_id: id,
          account_id: "a",
          created_ms: n * 200,
          restart_ms: n * 200 + 1000,
          reason: "voluntary",
          guarantee_id: nil,
          guaranteed_debt: 0
        }

        next = Account.record_bankruptcy(attached, event, true, false)

        assert_raise ArgumentError, fn ->
          apply(Account, :record_bankruptcy, [next, event, true, true])
        end

        next
      end)

    assert closed.bankruptcies == 5
    assert closed.suspended_ms == 1000
    assert Account.restart_at(closed, 100) == 1100
    assert Account.counted(closed, 1000 + Account.history_ms()) == 0
    assert Account.reinstate(closed, true).suspended_ms == nil
    assert_raise ArgumentError, fn -> apply(Account, :reinstate, [closed, false]) end
  end

  test "attachment and verification enforce supplied current facts" do
    account = Account.new("a", nil, false, 0)

    assert_raise ArgumentError, fn ->
      apply(Account, :attach_company, [account, "c", false, 0, 100])
    end

    attached = Account.attach_company(account, "c", true, 0, 100)

    assert_raise ArgumentError, fn ->
      apply(Account, :attach_company, [attached, "d", true, 0, 100])
    end

    assert_raise ArgumentError, fn ->
      apply(Account, :verify_email, [account, "a@example.com", true, true])
    end

    assert_raise ArgumentError, fn ->
      apply(Account, :verify_email, [account, "a@example.com", false, false])
    end

    assert Account.verify_email(account, "a@example.com", false, true).email == "a@example.com"
    assert {:error, :invalid_locale} = Account.set_locale(account, "unknown")
    assert {:ok, %{locale: "ar"}} = Account.set_locale(account, "ar")
  end
end
