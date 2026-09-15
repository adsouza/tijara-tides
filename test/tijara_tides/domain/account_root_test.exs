defmodule TijaraTides.Domain.AccountRootTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.Account
  alias Account.{BankruptcyEvent, Rows}

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
