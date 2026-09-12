defmodule TijaraTides.Domain.CompanyFinance do
  @moduledoc "Bank credit, active-clock installments, arrears and company receivership. All settlement is pure."
  import TijaraTides.Domain.State
  alias TijaraTides.Domain.{Journal, Notices}
  alias TijaraTides.Domain.CompanyFinance.{Guarantees, Loan, Installment}

  @fields ~w(id cash reserved unpaid profit account_id name created_ms last_invite_year unpaid_since arrears_since bankruptcy_ms)a
  @enforce_keys [:id, :cash, :reserved, :unpaid, :profit]
  defstruct @fields ++ [loans: [], installments: [], bills: [], pledges: []]
  @type t :: %__MODULE__{loans: [Loan.t()], installments: [Installment.t()]}

  @expenses ~w(cost_of_goods handling_expense cleaning_expense fuel_expense crew_expense spoilage_expense canal_expense interest_expense depreciation_expense ship_disposal_expense guarantee_expense)

  def from_row(row) do
    unknown = Map.keys(row) -- Enum.map(@fields, &Atom.to_string/1)
    if unknown != [], do: raise(ArgumentError, "Unknown company fields: #{inspect(unknown)}")

    struct!(
      __MODULE__,
      Map.new(@fields, fn key ->
        value =
          if key in @enforce_keys,
            do: Map.fetch!(row, Atom.to_string(key)),
            else: row[Atom.to_string(key)]

        {key, value}
      end)
    )
  end

  def to_row(%__MODULE__{} = finance),
    do: Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(finance, &1)})

  defp decode_child("loans", row), do: Loan.from_row(row)
  defp decode_child("loan_installments", row), do: Installment.from_row(row)
  defp decode_child(_, row), do: row
  defp encode_child(%Loan{} = child), do: Loan.to_row(child)
  defp encode_child(%Installment{} = child), do: Installment.to_row(child)
  defp encode_child(row), do: row

  # The one declaration of which struct field holds which owned entity kind.
  # Loading, isolating and saving the aggregate all derive their pairing here.
  @owned [
    loans: "loans",
    installments: "loan_installments",
    bills: "operating_bills",
    pledges: "guarantees"
  ]

  def from_world(state, company_id) do
    Enum.reduce(@owned, from_row(get(state, "companies", company_id)), fn {field, kind},
                                                                          finance ->
      Map.put(
        finance,
        field,
        Enum.map(owned(state, kind, "company_id", company_id), &decode_child(kind, &1))
      )
    end)
  end

  def open(state, row) do
    finance = from_row(row)

    unless is_nil(get(state, "companies", finance.id)) and
             Enum.all?(
               [finance.cash, finance.reserved, finance.unpaid, finance.profit],
               &(&1 == 0)
             ),
           do:
             raise(
               ArgumentError,
               "A new company must have zero financial balances and a new identity"
             )

    put(state, "companies", finance.id, row)
  end

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

  def post(state, company_id, kind, entries, context \\ %{}) do
    row = get(state, "companies", company_id) || raise(ArgumentError, "Missing financial owner")
    finance = row |> from_row() |> apply_entries(entries)

    row =
      Enum.reduce([:cash, :reserved, :unpaid, :profit], row, fn key, row ->
        Map.put(row, Atom.to_string(key), Map.fetch!(finance, key))
      end)

    row =
      Map.put(
        row,
        "unpaid_since",
        if(finance.unpaid > 0, do: row["unpaid_since"] || state.clock_ms)
      )

    state |> put("companies", company_id, row) |> Journal.post(company_id, kind, entries, context)
  end

  @doc "Settle a ship's operating costs without spending voyage reservations on crew."
  def ship_operations(state, company_id, ship_id, effects) do
    company = get(state, "companies", company_id) |> from_row()
    paid = min(effects.crew, available(company))

    state
    |> post(
      company_id,
      "ship_depreciation",
      [
        {"depreciation_expense", effects.depreciation},
        {"fleet", -effects.depreciation}
      ],
      %{ship: ship_id}
    )
    |> post(
      company_id,
      "operations",
      [
        {"fuel_expense", effects.fuel},
        {"cash_reserved", -effects.fuel},
        {"crew_expense", effects.crew},
        {"cash_available", -paid},
        {"payables", -(effects.crew - paid)},
        {"spoilage_expense", effects.spoilage},
        {"inventory", -effects.spoilage}
      ],
      %{ship: ship_id}
    )
    |> operating_bill(company_id, effects.crew - paid, state.clock_ms)
  end

  # Provisional lending policy; amounts are cents, durations are active-world ms.
  @terms %{
    period_ms: 86_400_000,
    installments: 4,
    rate_bps: 800,
    credit_limit: 25_000_000,
    credit_floor: 10_000_000,
    grace_ms: 86_400_000,
    cooldown_ms: 1_200_000,
    history_ms: TijaraTides.Domain.Account.history_ms()
  }
  def terms, do: @terms

  def rate(state, account) do
    count = counted(state, account)
    min(1600, 800 + min(count, 2) * 100 + max(0, count - 2) * 200)
  end

  def credit_limit(state, account),
    do: max(@terms.credit_floor, div(@terms.credit_limit, 1 + counted(state, account)))

  defdelegate history(state, account), to: TijaraTides.Domain.Account
  defdelegate counted(state, account), to: TijaraTides.Domain.Account
  defdelegate restart_at(state, account), to: TijaraTides.Domain.Account

  def loans(state, company),
    do:
      owned(state, "loans", "company_id", company)
      |> Enum.sort_by(&{&1["created_ms"], &1["id"]})

  def summary(state, account) do
    company = get(state, "companies", account["company_id"])

    loans = loans(state, account["company_id"])
    debt = Enum.sum(Enum.map(loans, & &1["remaining"]))
    base_limit = credit_limit(state, account)
    guarantee = Guarantees.active(state, account["id"])
    rate = rate(state, account)

    limit =
      cond do
        guarantee -> min(base_limit, guarantee["amount"])
        rate == 1600 -> 0
        true -> base_limit
      end

    arrears =
      Enum.sum(for l <- loans, l["status"] == "open", do: l["principal_due"] + l["interest_due"]) +
        if(company, do: company["unpaid"], else: 0)

    available =
      if company && not Guarantees.suspended?(account) && is_nil(company["bankruptcy_ms"]) &&
           arrears == 0,
         do: max(0, limit - debt),
         else: 0

    %{
      "can_declare_bankruptcy" => can_declare_bankruptcy?(state, account),
      "limit" => limit,
      "available" => available,
      "debt" => debt,
      "arrears" => arrears,
      "deadline" =>
        if(company && company["arrears_since"], do: company["arrears_since"] + @terms.grace_ms),
      "restart_ms" => restart_at(state, account),
      "rate_bps" => rate,
      "period_ms" => @terms.period_ms,
      "installments" => @terms.installments,
      "requires_guarantee" => rate == 1600 and is_nil(guarantee),
      "loans" =>
        Enum.map(loans, fn loan ->
          loan
          |> Map.put("schedule", schedule(loan))
          |> Map.put("actions", loan_actions(company, loan))
        end)
    }
  end

  defdelegate loan_actions(company, loan), to: __MODULE__.LoanActions, as: :for_loan

  defp schedule(loan) do
    if loan["status"] == "open" do
      {rows, _} =
        Enum.map_reduce(
          List.duplicate(nil, loan["periods_left"]) |> Enum.with_index(),
          {max(0, loan["remaining"] - loan["principal_due"]), loan["interest_remainder"]},
          fn {_, index}, {remaining, carry} ->
            principal = min(loan["installment"], remaining)

            elapsed =
              if index == 0,
                do: max(0, loan["next_due_ms"] - loan["interest_at_ms"]),
                else: loan["period_ms"]

            denominator = loan["period_ms"] * 10_000
            numerator = carry + remaining * loan["rate_bps"] * elapsed
            interest = max(0, div(numerator + denominator - 1, denominator))

            {%{
               "due_ms" => loan["next_due_ms"] + index * loan["period_ms"],
               "principal" => principal,
               "interest" => interest + if(index == 0, do: loan["interest_accrued"], else: 0)
             }, {remaining - principal, numerator - interest * denominator}}
          end
        )

      rows
    else
      []
    end
  end

  def borrow(state, account, amount, id) do
    facts = %{
      account_id: account["id"],
      available: summary(state, account)["available"],
      rate_bps: rate(state, account),
      suspended: Guarantees.suspended?(get(state, "accounts", account["id"]))
    }

    loan_command(state, account, {:borrow, amount, id, facts})
  end

  def repay(state, account, id), do: loan_command(state, account, {:repay, id})
  def recast(state, account, id, amount), do: loan_command(state, account, {:recast, id, amount})

  defp loan_command(state, account, operation) do
    company = get(state, "companies", account["company_id"])

    if is_nil(company) do
      {:error, if(elem(operation, 0) == :borrow, do: :finance_no_company, else: :loan_not_owned)}
    else
      with {:ok, next, effects, result} <-
             loan_transition(
               from_world(state, company["id"]),
               account["id"],
               operation,
               state.clock_ms
             ) do
        {:ok, save_finances(state, next, effects), result}
      end
    end
  end

  @doc "Loan transitions receive only the financial root, authenticated owner and explicit credit facts."
  def loan_transition(%__MODULE__{} = finance, owner, operation, now) do
    local = local_state(finance, now)
    account = %{"id" => owner, "company_id" => finance.id}

    result =
      case operation do
        {:borrow, amount, id, facts} -> borrow_owned(local, account, amount, id, facts)
        {:repay, id} -> repay_owned(local, account, id)
        {:recast, id, amount} -> recast_owned(local, account, id, amount)
      end

    # Write effects only: a loan transition has no caller that can coordinate
    # receivership, so it must not report a flag nothing acts on.
    with {:ok, changed, reply} <- result do
      {:ok, from_world(changed, finance.id), write_effects(changed), reply}
    end
  end

  defp borrow_owned(state, account, amount, id, facts) do
    company = get(state, "companies", account["company_id"])

    cond do
      facts.suspended ->
        {:error, :account_suspended}

      is_nil(company) or company["account_id"] != account["id"] or company["bankruptcy_ms"] != nil ->
        {:error, :finance_no_company}

      not is_integer(amount) or amount < 100 ->
        {:error, :loan_invalid_amount}

      amount > facts.available ->
        {:error, :loan_limit}

      length(Enum.filter(loans(state, company["id"]), &(&1["status"] == "open"))) >= 8 ->
        {:error, :loan_count_limit}

      true ->
        loan = %Loan{
          id: id,
          company_id: company["id"],
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
          installment: div(amount + @terms.installments - 1, @terms.installments),
          status: "open",
          created_ms: state.clock_ms
        }

        state =
          state
          |> put("loans", id, Loan.to_row(loan))
          |> __MODULE__.post(company["id"], "loan_draw", [
            {"cash_available", amount},
            {"loan_principal", -amount}
          ])

        {:ok, state, %{"loan_id" => id, "borrowed" => amount}}
    end
  end

  defp repay_owned(state, account, id) do
    company = get(state, "companies", account["company_id"])
    loan = get(state, "loans", id) |> Loan.from_row()

    cond do
      is_nil(company) or company["account_id"] != account["id"] or is_nil(loan) or
          loan.company_id != company["id"] ->
        {:error, :loan_not_owned}

      loan.status == "repaid" ->
        {:ok, state, %{"repaid" => 0}}

      loan.status != "open" ->
        {:error, :loan_not_owned}

      not loan_actions(company, Loan.to_row(loan))["repay_enabled"] ->
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
    company = get(state, "companies", account["company_id"])
    loan = get(state, "loans", id) |> Loan.from_row()
    actions = if company && loan, do: loan_actions(company, Loan.to_row(loan)), else: %{}

    cond do
      is_nil(company) or company["account_id"] != account["id"] or is_nil(loan) or
        loan.company_id != company["id"] or loan.status != "open" or
          company["bankruptcy_ms"] != nil ->
        {:error, :loan_not_owned}

      not actions["recast_allowed"] ->
        {:error, :loan_recast_unavailable}

      not is_integer(amount) or amount < actions["recast_min"] or
          amount > actions["recast_balance"] ->
        {:error, :loan_recast_amount}

      amount > company["cash"] - company["reserved"] ->
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

        loan = get(state, "loans", id) |> Loan.from_row()
        installment = div(loan.remaining + loan.periods_left - 1, loan.periods_left)
        state = put(state, "loans", id, Loan.to_row(%{loan | installment: installment}))

        {:ok, state,
         %{"paid" => amount, "principal_reduction" => principal, "installment" => installment}}
    end
  end

  @doc "Settle only this loaded financial aggregate; return coordination effects separately."
  def settle_finances(%__MODULE__{} = finance, now) do
    local = local_state(finance, now)
    local = Enum.reduce(finance.loans, local, &accrue(&2, &1))

    local =
      if to_row(finance)["bankruptcy_ms"] == nil,
        do: settle_company(local, finance.id),
        else: local

    {from_world(local, finance.id), financial_effects(local, finance.id)}
  end

  defp local_state(finance, now) do
    entities =
      Enum.reduce(@owned, %{"companies" => %{finance.id => to_row(finance)}}, fn {field, kind},
                                                                                 entities ->
        Map.put(
          entities,
          kind,
          Map.new(Map.fetch!(finance, field), fn child ->
            row = encode_child(child)
            {row["id"], row}
          end)
        )
      end)

    %{entities: entities, clock_ms: now} |> TijaraTides.Domain.EntityIndex.rebuild()
  end

  # Rows the world adapter must write back, each notice keyed as the aggregate keyed it.
  defp write_effects(local),
    do: %{
      journal: Map.get(local, :journal, []),
      notices: Map.to_list(entities(local, "notices")),
      children:
        for(
          {{kind, id}, operation} <- TijaraTides.Domain.ChangeSet.since(%{}, local),
          kind in Keyword.values(@owned),
          do: {kind, id, operation, get(local, kind, id)}
        )
    }

  defp financial_effects(local, id) do
    row = get(local, "companies", id)

    Map.put(
      write_effects(local),
      :receivership,
      row["bankruptcy_ms"] == nil and row["arrears_since"] != nil and
        local.clock_ms >= row["arrears_since"] + @terms.grace_ms
    )
  end

  def settle_owned(state, id) do
    {finance, effects} = settle_finances(from_world(state, id), state.clock_ms)
    {save_finances(state, finance, effects), effects}
  end

  defp save_finances(state, finance, effects) do
    id = finance.id
    state = put(state, "companies", id, to_row(finance))

    state =
      Enum.reduce(effects.children, state, fn {kind, child_id, operation, row}, state ->
        existing = get(state, kind, child_id)

        unless kind in Keyword.values(@owned) and
                 (existing == nil or existing["company_id"] == id) and
                 (row == nil or row["company_id"] == id),
               do:
                 raise(ArgumentError, "Financial transition cannot write another company's child")

        case operation do
          :put -> put(state, kind, child_id, row)
          :delete -> delete(state, kind, child_id)
        end
      end)

    state =
      Enum.reduce(effects.journal, state, fn event, state ->
        Journal.post(state, event.company, event.kind, event.entries, %{
          ship: event.ship,
          good: event.good
        })
      end)

    Enum.reduce(effects.notices, state, fn {notice_id, notice}, state ->
      Notices.notice(state, notice["account_id"], notice_id, notice["text"])
    end)
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

    company = get(state, "companies", loan.company_id)

    state =
      state
      |> put("loans", loan.id, Loan.to_row(loan))
      |> __MODULE__.post(company["id"], "loan_interest", [
        {"interest_expense", interest},
        {"loan_interest", -interest}
      ])

    if (scheduled and due <= state.clock_ms) or (not scheduled and loan.interest_accrued > 0) do
      bill_due = if scheduled, do: due, else: due - loan.period_ms
      id = loan.id <> ":" <> to_string(bill_due)
      old = get(state, "loan_installments", id) |> Installment.from_row()

      principal =
        if scheduled,
          do: min(loan.remaining - loan.principal_due, loan.installment),
          else: 0

      bill = %Installment{
        id: id,
        loan_id: loan.id,
        company_id: company["id"],
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
        |> put("loan_installments", id, Installment.to_row(bill))
        |> put("loans", loan.id, Loan.to_row(loan))

      if scheduled, do: accrue(state, loan), else: state
    else
      state
    end
  end

  defp accrue(state, _loan), do: state

  def operating_bill(state, _company, 0, _due), do: state

  def operating_bill(state, company, amount, due) do
    id = company <> ":" <> to_string(due)
    existing = get(state, "operating_bills", id)

    put(state, "operating_bills", id, %{
      "id" => id,
      "company_id" => company,
      "due_ms" => due,
      "remaining" => amount + if(existing, do: existing["remaining"], else: 0)
    })
  end

  defp settle_company(state, id) do
    company = get(state, "companies", id)

    operations =
      owned(state, "operating_bills", "company_id", id)

    unrecorded = company["unpaid"] - Enum.sum(Enum.map(operations, & &1["remaining"]))

    state =
      if unrecorded > 0,
        do: operating_bill(state, id, unrecorded, company["unpaid_since"] || state.clock_ms),
        else: state

    bills =
      for bill <- owned(state, "loan_installments", "company_id", id),
          do: {bill["due_ms"], {"loan", bill["id"]}}

    bills =
      bills ++
        for bill <- owned(state, "operating_bills", "company_id", id),
            bill["remaining"] > 0,
            do: {bill["due_ms"], {"operations", bill["id"]}}

    first_due = Enum.min(Enum.map(bills, &elem(&1, 0)), fn -> nil end)

    state =
      Enum.sort(bills)
      |> Enum.reduce(state, fn {_, bill}, state ->
        c = get(state, "companies", id)
        available = c["cash"] - c["reserved"]

        if elem(bill, 0) == "operations" do
          row = get(state, "operating_bills", elem(bill, 1))
          paid = min(available, row["remaining"])

          state =
            if paid == row["remaining"],
              do: delete(state, "operating_bills", row["id"]),
              else:
                put(state, "operating_bills", row["id"], %{
                  row
                  | "remaining" => row["remaining"] - paid
                })

          state
          |> __MODULE__.post(id, "operating_repayment", [
            {"payables", paid},
            {"cash_available", -paid}
          ])
        else
          row = get(state, "loan_installments", elem(bill, 1))

          pay_loan(
            state,
            Loan.from_row(get(state, "loans", row["loan_id"])),
            available,
            Installment.from_row(row)
          )
        end
      end)

    company = get(state, "companies", id)

    remaining =
      company["unpaid"] +
        Enum.sum(for l <- loans(state, id), do: l["principal_due"] + l["interest_due"])

    since = if remaining > 0, do: company["arrears_since"] || first_due

    prior_since = company["arrears_since"]

    company =
      company
      |> Map.put("arrears_since", since)
      |> Map.put(
        "unpaid_since",
        if(company["unpaid"] > 0, do: company["unpaid_since"] || first_due)
      )

    state = put(state, "companies", id, company)

    cond do
      since && state.clock_ms >= since + @terms.grace_ms ->
        state

      since == nil and prior_since != nil ->
        Notices.notice(
          state,
          company["account_id"],
          "arrears:" <> id,
          "All overdue payments have been cleared. The bankruptcy grace period has ended."
        )

      since != nil and prior_since != since ->
        Notices.notice(
          state,
          company["account_id"],
          "arrears:" <> id,
          "Payments overdue. Clear all arrears within #{div(max(0, since + @terms.grace_ms - state.clock_ms), 60_000)} active-world minutes to avoid bankruptcy."
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
          do: delete(state, "loan_installments", bill.id),
          else: put(state, "loan_installments", bill.id, Installment.to_row(bill))
      else
        Enum.reduce(entities(state, "loan_installments"), state, fn {id, bill}, state ->
          if bill["loan_id"] == loan.id,
            do: delete(state, "loan_installments", id),
            else: state
        end)
      end

    c = get(state, "companies", loan.company_id)

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
    |> put("loans", loan.id, Loan.to_row(loan))
    |> __MODULE__.post(c["id"], "loan_repayment", [
      {"loan_principal", principal},
      {"loan_interest", interest},
      {"cash_available", -principal - interest}
    ])
  end

  def can_declare_bankruptcy?(state, account) do
    company = get(state, "companies", account["company_id"])

    if company && company["account_id"] == account["id"] && is_nil(company["bankruptcy_ms"]) do
      liabilities =
        company["unpaid"] +
          Enum.sum(
            for loan <- loans(state, company["id"]),
                do: loan["remaining"] + loan["interest_due"] + loan["interest_accrued"]
          )

      company["cash"] - company["reserved"] < liabilities
    else
      false
    end
  end

  def close_in_receivership(state, company_id) do
    company = get(state, "companies", company_id)
    account = get(state, "accounts", company["account_id"])

    state =
      Enum.reduce(loans(state, company["id"]), state, fn loan, state ->
        state
        |> put("loans", loan["id"], %{
          loan
          | "remaining" => 0,
            "principal_due" => 0,
            "interest_due" => 0,
            "interest_accrued" => 0,
            "overdue_ms" => nil,
            "status" => if(loan["status"] == "repaid", do: "repaid", else: "defaulted")
        })
        |> __MODULE__.post(company["id"], "bankruptcy_debt", [
          {"loan_principal", loan["remaining"]},
          {"loan_interest", loan["interest_due"] + loan["interest_accrued"]},
          {"receivership", -loan["remaining"] - loan["interest_due"] - loan["interest_accrued"]}
        ])
      end)

    state =
      Enum.reduce(
        ["operating_bills", "loan_installments"],
        state,
        fn kind, state ->
          Enum.reduce(entities(state, kind), state, fn {id, row}, state ->
            if row["company_id"] == company["id"], do: delete(state, kind, id), else: state
          end)
        end
      )

    state =
      state
      |> put(
        "companies",
        company["id"],
        company
        |> Map.put("bankruptcy_ms", state.clock_ms)
        |> Map.put("arrears_since", nil)
        |> Map.put("unpaid_since", nil)
      )
      |> __MODULE__.post(company["id"], "bankruptcy_payables", [
        {"payables", company["unpaid"]},
        {"receivership", -company["unpaid"]}
      ])
      |> Notices.notice(
        account["id"],
        "bankruptcy:" <> company["id"],
        "#{company["name"]} is in bankruptcy. Its assets remain in receivership. A replacement company becomes available after 20 active-world minutes."
      )

    state
  end
end
