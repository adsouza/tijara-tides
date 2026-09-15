defmodule TijaraTides.Domain.CompanyFinance do
  @moduledoc "Typed financial balances, loan transitions and ordered debt settlement."
  alias TijaraTides.Domain.Journal
  alias __MODULE__.{Loan, Installment, OperatingBill, Guarantee, Transition}
  import Transition, only: [get: 3, put: 4, delete: 3, owned: 4, entities: 2]

  @fields ~w(id cash reserved unpaid profit account_id name created_ms last_invite_year unpaid_since arrears_since bankruptcy_ms)a
  @enforce_keys [:id, :cash, :reserved, :unpaid, :profit]
  defstruct @fields ++ [loans: [], installments: [], bills: [], pledges: []]

  @type t :: %__MODULE__{
          loans: [Loan.t()],
          installments: [Installment.t()],
          bills: [OperatingBill.t()],
          pledges: [Guarantee.t()]
        }

  @expenses ~w(rent_expense cost_of_goods handling_expense cleaning_expense fuel_expense crew_expense spoilage_expense canal_expense interest_expense depreciation_expense ship_disposal_expense guarantee_expense)

  def available(%__MODULE__{} = finance), do: finance.cash - finance.reserved

  @doc "Apply balanced accounting entries to the financial root before recording them."
  def apply_entries(%__MODULE__{} = finance, entries) do
    unless Enum.all?(entries, fn {_, amount} -> is_integer(amount) end) and
             Enum.sum(Enum.map(entries, &elem(&1, 1))) == 0,
           do: raise(ArgumentError, "Financial settlement requires balanced integer entries")

    next =
      Enum.reduce(entries, finance, fn
        {"cash_available", amount}, f ->
          %{f | cash: f.cash + amount}

        {"cash_reserved", amount}, f ->
          %{f | cash: f.cash + amount, reserved: f.reserved + amount}

        {"payables", amount}, f ->
          %{f | unpaid: f.unpaid - amount}

        {"sales_revenue", amount}, f ->
          %{f | profit: f.profit - amount}

        {code, amount}, f when code in @expenses ->
          %{f | profit: f.profit - amount}

        _, f ->
          f
      end)

    unless next.reserved >= 0 and next.unpaid >= 0 and available(next) >= 0,
      do:
        raise(
          ArgumentError,
          "Financial settlement exceeds available cash, reservations or payables"
        )

    next
  end

  # Provisional lending policy; amounts are cents, durations are active-world ms.
  @terms %{
    period_ms: 86_400_000,
    installments: 4,
    rate_bps: 800,
    credit_limit: 25_000_000,
    credit_floor: 10_000_000,
    grace_ms: 86_400_000,
    cooldown_ms: 180_000,
    history_ms: TijaraTides.Domain.Account.history_ms()
  }
  def terms, do: @terms

  def rate(count), do: min(1600, 800 + min(count, 2) * 100 + max(0, count - 2) * 200)
  def credit_limit(count), do: max(@terms.credit_floor, div(@terms.credit_limit, 1 + count))

  def open(%__MODULE__{} = finance, id_taken?) do
    unless not id_taken? and
             Enum.all?(
               [finance.cash, finance.reserved, finance.unpaid, finance.profit],
               &(&1 == 0)
             ),
           do:
             raise(
               ArgumentError,
               "A new company must have zero financial balances and a new identity"
             )

    finance
  end

  def post_entries(%__MODULE__{} = finance, entries, now) do
    next = apply_entries(finance, entries)
    %{next | unpaid_since: if(next.unpaid > 0, do: finance.unpaid_since || now)}
  end

  defdelegate loan_actions(company, loan), to: __MODULE__.LoanActions, as: :for_loan

  @doc "Loan transitions receive only the financial root, authenticated owner and explicit credit facts."
  def loan_transition(%__MODULE__{} = finance, owner, operation, now) do
    local = Transition.new(finance, now)
    account = %{id: owner, company_id: finance.id}

    result =
      case operation do
        {:borrow, amount, id, facts} -> borrow_owned(local, account, amount, id, facts)
        {:repay, id} -> repay_owned(local, account, id)
        {:recast, id, amount} -> recast_owned(local, account, id, amount)
      end

    # Write effects only: a loan transition has no caller that can coordinate
    # receivership, so it must not report a flag nothing acts on.
    with {:ok, changed, reply} <- result do
      {:ok, Transition.finance(changed), Transition.effects(changed), reply}
    end
  end

  defp borrow_owned(state, account, amount, id, facts) do
    company = get(state, :company, account.company_id)

    cond do
      facts.suspended ->
        {:error, :account_suspended}

      is_nil(company) or company.account_id != account.id or company.bankruptcy_ms != nil ->
        {:error, :finance_no_company}

      not is_integer(amount) or amount < 100 ->
        {:error, :loan_invalid_amount}

      amount > facts.available ->
        {:error, :loan_limit}

      length(open_loans(state, company.id)) >= 8 ->
        {:error, :loan_count_limit}

      true ->
        loan = %Loan{
          id: id,
          company_id: company.id,
          principal: amount,
          remaining: amount,
          principal_due: 0,
          interest_due: 0,
          interest_accrued: 0,
          interest_remainder: 0,
          interest_at_ms: state.clock_ms,
          overdue_ms: nil,
          next_due_ms: state.clock_ms + @terms.period_ms,
          period_ms: @terms.period_ms,
          periods_left: @terms.installments,
          rate_bps: facts.rate_bps,
          guarantee_id: Map.get(facts, :guarantee_id),
          installment: div(amount + @terms.installments - 1, @terms.installments),
          status: "open",
          created_ms: state.clock_ms
        }

        state =
          state
          |> put(:loans, id, loan)
          |> post(company.id, "loan_draw", [
            {"cash_available", amount},
            {"loan_principal", -amount}
          ])

        {:ok, state, %{"loan_id" => id, "borrowed" => amount}}
    end
  end

  defp repay_owned(state, account, id) do
    company = get(state, :company, account.company_id)
    loan = get(state, :loans, id)

    cond do
      is_nil(company) or company.account_id != account.id or is_nil(loan) or
          loan.company_id != company.id ->
        {:error, :loan_not_owned}

      loan.status == "repaid" ->
        {:ok, state, %{"repaid" => 0}}

      loan.status != "open" ->
        {:error, :loan_not_owned}

      not loan_actions(company, loan)["repay_enabled"] ->
        {:error, :loan_repayment_funds}

      true ->
        amount = loan.remaining + loan.interest_due + loan.interest_accrued

        state =
          pay_loan(
            state,
            %{
              loan
              | principal_due: loan.remaining,
                interest_due: loan.interest_due + loan.interest_accrued,
                interest_accrued: 0
            },
            amount
          )

        {:ok, state, %{"repaid" => amount}}
    end
  end

  defp recast_owned(state, account, id, amount) do
    company = get(state, :company, account.company_id)
    loan = get(state, :loans, id)
    actions = if company && loan, do: loan_actions(company, loan), else: %{}

    cond do
      is_nil(company) or company.account_id != account.id or is_nil(loan) or
        loan.company_id != company.id or loan.status != "open" or
          company.bankruptcy_ms != nil ->
        {:error, :loan_not_owned}

      not actions["recast_allowed"] ->
        {:error, :loan_recast_unavailable}

      not is_integer(amount) or amount < actions["recast_min"] or
          amount > actions["recast_balance"] ->
        {:error, :loan_recast_amount}

      amount > company.cash - company.reserved ->
        {:error, :loan_repayment_funds}

      amount == loan.remaining + loan.interest_accrued ->
        repay_owned(state, account, id)

      true ->
        principal = amount - loan.interest_accrued

        state =
          pay_loan(
            state,
            %{
              loan
              | principal_due: principal,
                interest_due: loan.interest_accrued,
                interest_accrued: 0
            },
            amount
          )

        loan = get(state, :loans, id)
        installment = div(loan.remaining + loan.periods_left - 1, loan.periods_left)
        state = put(state, :loans, id, %{loan | installment: installment})

        {:ok, state,
         %{"paid" => amount, "principal_reduction" => principal, "installment" => installment}}
    end
  end

  @doc "Settle only this loaded financial aggregate; return coordination effects separately."
  def settle_finances(%__MODULE__{} = finance, now) do
    local = Transition.new(finance, now)
    local = Enum.reduce(finance.loans, local, &accrue(&2, &1))

    local =
      if finance.bankruptcy_ms == nil,
        do: settle_company(local, finance.id),
        else: local

    {Transition.finance(local), financial_effects(local)}
  end

  defp accrue(state, %Loan{status: "open"} = loan) do
    due = loan.next_due_ms
    scheduled = loan.periods_left > 0
    until = if scheduled, do: min(state.clock_ms, due), else: state.clock_ms
    denominator = loan.period_ms * 10_000

    numerator =
      loan.interest_remainder +
        max(0, until - loan.interest_at_ms) * loan.remaining * loan.rate_bps

    # Round cumulative interest up to cents, carrying the fractional credit so
    # tick frequency never changes the total and short loans are not free.
    interest = max(0, div(numerator + denominator - 1, denominator))

    loan = %{
      loan
      | interest_accrued: loan.interest_accrued + interest,
        interest_remainder: numerator - interest * denominator,
        interest_at_ms: until
    }

    company = get(state, :company, loan.company_id)

    state =
      state
      |> put(:loans, loan.id, loan)
      |> post(company.id, "loan_interest", [
        {"interest_expense", interest},
        {"loan_interest", -interest}
      ])

    if (scheduled and due <= state.clock_ms) or (not scheduled and loan.interest_accrued > 0) do
      bill_due = if scheduled, do: due, else: due - loan.period_ms
      id = loan.id <> ":" <> to_string(bill_due)
      old = get(state, :installments, id)

      principal =
        if scheduled,
          do: min(loan.remaining - loan.principal_due, loan.installment),
          else: 0

      bill = %Installment{
        id: id,
        loan_id: loan.id,
        company_id: company.id,
        due_ms: bill_due,
        principal_due: if(old, do: old.principal_due, else: 0) + principal,
        interest_due: if(old, do: old.interest_due, else: 0) + loan.interest_accrued
      }

      loan = %{
        loan
        | principal_due: loan.principal_due + principal,
          interest_due: loan.interest_due + loan.interest_accrued,
          interest_accrued: 0,
          overdue_ms: loan.overdue_ms || bill_due,
          next_due_ms: if(scheduled, do: due + loan.period_ms, else: due),
          periods_left: max(0, loan.periods_left - 1)
      }

      state =
        state
        |> put(:installments, id, bill)
        |> put(:loans, loan.id, loan)

      if scheduled, do: accrue(state, loan), else: state
    else
      state
    end
  end

  defp accrue(state, _loan), do: state

  defp operating_bill(state, _company, 0, _due), do: state

  defp operating_bill(state, company, amount, due) do
    id = company <> ":" <> to_string(due)
    existing = get(state, :bills, id)

    put(state, :bills, id, %OperatingBill{
      id: id,
      company_id: company,
      due_ms: due,
      remaining: amount + if(existing, do: existing.remaining, else: 0)
    })
  end

  defp settle_company(state, id) do
    company = get(state, :company, id)

    operations =
      owned(state, :bills, :company_id, id)

    unrecorded = company.unpaid - Enum.sum(Enum.map(operations, & &1.remaining))

    state =
      if unrecorded > 0,
        do: operating_bill(state, id, unrecorded, company.unpaid_since || state.clock_ms),
        else: state

    bills =
      for bill <- owned(state, :installments, :company_id, id),
          do: {bill.due_ms, {"loan", bill.id}}

    bills =
      bills ++
        for bill <- owned(state, :bills, :company_id, id),
            bill.remaining > 0,
            do: {bill.due_ms, {"operations", bill.id}}

    first_due = Enum.min(Enum.map(bills, &elem(&1, 0)), fn -> nil end)

    state =
      Enum.sort(bills)
      |> Enum.reduce(state, fn {_, bill}, state ->
        c = get(state, :company, id)
        available = c.cash - c.reserved

        if elem(bill, 0) == "operations" do
          row = get(state, :bills, elem(bill, 1))
          paid = min(available, row.remaining)

          state =
            if paid == row.remaining,
              do: delete(state, :bills, row.id),
              else:
                put(
                  state,
                  :bills,
                  row.id,
                  row
                  |> OperatingBill.pay(paid)
                )

          state
          |> post(id, "operating_repayment", [
            {"payables", paid},
            {"cash_available", -paid}
          ])
        else
          row = get(state, :installments, elem(bill, 1))

          pay_loan(
            state,
            get(state, :loans, row.loan_id),
            available,
            row
          )
        end
      end)

    company = get(state, :company, id)

    remaining =
      company.unpaid +
        Enum.sum(for l <- loans(state, id), do: l.principal_due + l.interest_due)

    since = if remaining > 0, do: company.arrears_since || first_due

    prior_since = company.arrears_since

    company =
      company
      |> Map.put(:arrears_since, since)
      |> Map.put(
        :unpaid_since,
        if(company.unpaid > 0, do: company.unpaid_since || first_due)
      )

    state = put(state, :company, id, company)

    cond do
      since && state.clock_ms >= since + @terms.grace_ms ->
        state

      since == nil and prior_since != nil ->
        notice(
          state,
          company.account_id,
          "arrears:" <> id,
          {"finance.arrears_cleared", %{}}
        )

      since != nil and prior_since != since ->
        notice(
          state,
          company.account_id,
          "arrears:" <> id,
          {"finance.arrears",
           %{"minutes" => div(max(0, since + @terms.grace_ms - state.clock_ms), 60_000)}}
        )

      true ->
        state
    end
  end

  defp pay_loan(state, %Loan{} = loan, available, bill \\ nil) do
    interest = min(available, (bill || loan).interest_due)
    principal = min(available - interest, (bill || loan).principal_due)

    state =
      if bill do
        bill = %{
          bill
          | principal_due: bill.principal_due - principal,
            interest_due: bill.interest_due - interest
        }

        if bill.principal_due + bill.interest_due == 0,
          do: delete(state, :installments, bill.id),
          else: put(state, :installments, bill.id, bill)
      else
        Enum.reduce(entities(state, :installments), state, fn {id, bill}, state ->
          if bill.loan_id == loan.id,
            do: delete(state, :installments, id),
            else: state
        end)
      end

    c = get(state, :company, loan.company_id)

    loan = %{
      loan
      | interest_due: loan.interest_due - interest,
        principal_due: loan.principal_due - principal,
        remaining: loan.remaining - principal
    }

    loan = %{
      loan
      | status: if(loan.remaining == 0 and loan.interest_due == 0, do: "repaid", else: "open"),
        overdue_ms: if(loan.principal_due + loan.interest_due > 0, do: loan.overdue_ms)
    }

    state
    |> put(:loans, loan.id, loan)
    |> post(c.id, "loan_repayment", [
      {"loan_principal", principal},
      {"loan_interest", interest},
      {"cash_available", -principal - interest}
    ])
  end

  defp open_loans(state, id),
    do:
      owned(state, :loans, :company_id, id)
      |> Enum.filter(&(&1.status == "open"))
      |> Enum.sort_by(&{&1.created_ms, &1.id})

  defp loans(state, id),
    do: owned(state, :loans, :company_id, id) |> Enum.sort_by(&{&1.created_ms, &1.id})

  defp post(state, company_id, kind, entries, context \\ %{}) do
    next = post_entries(state.finance, entries, state.clock_ms)
    state |> put(:company, company_id, next) |> Journal.post(company_id, kind, entries, context)
  end

  defp notice(state, nil, _id, _payload), do: state

  defp notice(state, account_id, id, payload),
    do: %{
      state
      | notices: Map.put(state.notices, id, %{account_id: account_id, payload: payload})
    }

  defp financial_effects(state) do
    finance = state.finance

    Map.put(
      Transition.effects(state),
      :receivership,
      finance.bankruptcy_ms == nil and finance.arrears_since != nil and
        state.clock_ms >= finance.arrears_since + @terms.grace_ms
    )
  end

  def close_in_receivership(%__MODULE__{} = finance, now) do
    local = Transition.new(finance, now)

    local =
      Enum.reduce(loans(local, finance.id), local, fn loan, acc ->
        closed = %{
          loan
          | remaining: 0,
            principal_due: 0,
            interest_due: 0,
            interest_accrued: 0,
            overdue_ms: nil,
            status: if(loan.status == "repaid", do: "repaid", else: "defaulted")
        }

        acc
        |> put(:loans, loan.id, closed)
        |> post(finance.id, "bankruptcy_debt", [
          {"loan_principal", loan.remaining},
          {"loan_interest", loan.interest_due + loan.interest_accrued},
          {"receivership", -loan.remaining - loan.interest_due - loan.interest_accrued}
        ])
      end)

    local =
      Enum.reduce([:bills, :installments], local, fn kind, acc ->
        Enum.reduce(entities(acc, kind), acc, fn {id, _}, acc -> delete(acc, kind, id) end)
      end)

    closed = %{local.finance | bankruptcy_ms: now, arrears_since: nil, unpaid_since: nil}

    local =
      local
      |> put(:company, finance.id, closed)
      |> post(finance.id, "bankruptcy_payables", [
        {"payables", finance.unpaid},
        {"receivership", -finance.unpaid}
      ])

    {Transition.finance(local), Transition.effects(local)}
  end
end
