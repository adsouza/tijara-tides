defmodule TijaraTides.Domain.Finance do
  @moduledoc "Bank credit, active-clock installments, arrears and company receivership. All settlement is pure."
  import TijaraTides.Domain.State
  alias TijaraTides.Domain.{Journal, Notices, Guarantees}
  # Provisional lending policy; amounts are cents, durations are active-world ms.
  @terms %{
    period_ms: 86_400_000,
    installments: 4,
    rate_bps: 800,
    credit_limit: 25_000_000,
    credit_floor: 10_000_000,
    grace_ms: 86_400_000,
    cooldown_ms: 1_200_000,
    history_ms: 112 * 86_400_000
  }
  def terms, do: @terms

  def rate(state, account) do
    count = counted(state, account)
    min(1600, 800 + min(count, 2) * 100 + max(0, count - 2) * 200)
  end

  def credit_limit(state, account),
    do: max(@terms.credit_floor, div(@terms.credit_limit, 1 + counted(state, account)))

  def history(state, account) do
    entities(state, "bankruptcy_events")
    |> Map.values()
    |> Enum.filter(&(&1["account_id"] == account["id"]))
  end

  def counted(state, account),
    do:
      Enum.count(
        history(state, account),
        &(&1["created_ms"] + @terms.history_ms > state.clock_ms)
      )

  def restart_at(state, account),
    do: history(state, account) |> Enum.map(& &1["restart_ms"]) |> Enum.max(fn -> 0 end)

  def loans(state, company),
    do:
      entities(state, "loans")
      |> Map.values()
      |> Enum.filter(&(&1["company_id"] == company))
      |> Enum.sort_by(&{&1["created_ms"], &1["id"]})

  def summary(state, account) do
    company = get(state, "companies", account["company_id"])

    loans = loans(state, account["company_id"])
    debt = Enum.sum(Enum.map(loans, & &1["remaining"]))
    base_limit = credit_limit(state, account)
    guarantee = Guarantees.active(state, account["id"])

    limit =
      cond do
        guarantee -> min(base_limit, guarantee["amount"])
        rate(state, account) == 1600 -> 0
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
      "rate_bps" => rate(state, account),
      "period_ms" => @terms.period_ms,
      "installments" => @terms.installments,
      "loans" => Enum.map(loans, &Map.put(&1, "schedule", schedule(&1)))
    }
  end

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
    state = settle(state)
    company = get(state, "companies", account["company_id"])

    cond do
      Guarantees.suspended?(get(state, "accounts", account["id"])) ->
        {:error, :account_suspended}

      is_nil(company) or company["account_id"] != account["id"] or company["bankruptcy_ms"] != nil ->
        {:error, :finance_no_company}

      not is_integer(amount) or amount < 100 ->
        {:error, :loan_invalid_amount}

      amount > summary(state, account)["available"] ->
        {:error, :loan_limit}

      length(Enum.filter(loans(state, company["id"]), &(&1["status"] == "open"))) >= 8 ->
        {:error, :loan_count_limit}

      true ->
        loan = %{
          "id" => id,
          "company_id" => company["id"],
          "principal" => amount,
          "remaining" => amount,
          "principal_due" => 0,
          "interest_due" => 0,
          "interest_accrued" => 0,
          "interest_remainder" => 0,
          "interest_at_ms" => state.clock_ms,
          "overdue_ms" => nil,
          "next_due_ms" => state.clock_ms + @terms.period_ms,
          "period_ms" => @terms.period_ms,
          "periods_left" => @terms.installments,
          "rate_bps" => rate(state, account),
          "installment" => div(amount + @terms.installments - 1, @terms.installments),
          "status" => "open",
          "created_ms" => state.clock_ms
        }

        state =
          state
          |> put("loans", id, loan)
          |> put("companies", company["id"], %{company | "cash" => company["cash"] + amount})
          |> Journal.post(company["id"], "loan_draw", [
            {"cash_available", amount},
            {"loan_principal", -amount}
          ])

        {:ok, Guarantees.drawn(state, account), %{"loan_id" => id, "borrowed" => amount}}
    end
  end

  def repay(state, account, id) do
    state = settle(state)
    company = get(state, "companies", account["company_id"])
    loan = get(state, "loans", id)

    cond do
      is_nil(company) or company["account_id"] != account["id"] or is_nil(loan) or
          loan["company_id"] != company["id"] ->
        {:error, :loan_not_owned}

      loan["status"] == "repaid" ->
        {:ok, state, %{"repaid" => 0}}

      loan["status"] != "open" ->
        {:error, :loan_not_owned}

      company["cash"] - company["reserved"] <
          loan["remaining"] + loan["interest_due"] + loan["interest_accrued"] ->
        {:error, :loan_repayment_funds}

      true ->
        amount = loan["remaining"] + loan["interest_due"] + loan["interest_accrued"]

        state =
          pay_loan(
            state,
            %{
              loan
              | "principal_due" => loan["remaining"],
                "interest_due" => loan["interest_due"] + loan["interest_accrued"],
                "interest_accrued" => 0
            },
            amount
          )

        {:ok, settle(state), %{"repaid" => amount}}
    end
  end

  def recast(state, account, id, amount) do
    state = settle(state)
    company = get(state, "companies", account["company_id"])
    loan = get(state, "loans", id)

    cond do
      is_nil(company) or company["account_id"] != account["id"] or is_nil(loan) or
        loan["company_id"] != company["id"] or loan["status"] != "open" or
          company["bankruptcy_ms"] != nil ->
        {:error, :loan_not_owned}

      loan["periods_left"] < 1 or loan["principal_due"] > 0 or loan["interest_due"] > 0 or
          company["unpaid"] > 0 ->
        {:error, :loan_recast_unavailable}

      not is_integer(amount) or amount < loan["interest_accrued"] + 100 or
          amount > loan["remaining"] + loan["interest_accrued"] ->
        {:error, :loan_recast_amount}

      amount > company["cash"] - company["reserved"] ->
        {:error, :loan_repayment_funds}

      amount == loan["remaining"] + loan["interest_accrued"] ->
        repay(state, account, id)

      true ->
        principal = amount - loan["interest_accrued"]

        state =
          pay_loan(
            state,
            %{
              loan
              | "principal_due" => principal,
                "interest_due" => loan["interest_accrued"],
                "interest_accrued" => 0
            },
            amount
          )

        loan = get(state, "loans", id)
        installment = div(loan["remaining"] + loan["periods_left"] - 1, loan["periods_left"])
        state = put(state, "loans", id, %{loan | "installment" => installment})

        {:ok, state,
         %{"paid" => amount, "principal_reduction" => principal, "installment" => installment}}
    end
  end

  def settle(state) do
    state =
      Enum.reduce(entities(state, "loans"), state, fn {_, loan}, state -> accrue(state, loan) end)

    Enum.reduce(entities(state, "companies"), state, fn {id, company}, state ->
      if company["bankruptcy_ms"] == nil, do: settle_company(state, id), else: state
    end)
    |> Guarantees.settle()
  end

  defp accrue(state, %{"status" => "open"} = loan) do
    due = loan["next_due_ms"]
    scheduled = loan["periods_left"] > 0
    until = if scheduled, do: min(state.clock_ms, due), else: state.clock_ms
    denominator = loan["period_ms"] * 10_000

    numerator =
      loan["interest_remainder"] +
        max(0, until - loan["interest_at_ms"]) * loan["remaining"] * loan["rate_bps"]

    # Round cumulative interest up to cents, carrying the fractional credit so
    # tick frequency never changes the total and short loans are not free.
    interest = max(0, div(numerator + denominator - 1, denominator))

    loan = %{
      loan
      | "interest_accrued" => loan["interest_accrued"] + interest,
        "interest_remainder" => numerator - interest * denominator,
        "interest_at_ms" => until
    }

    company = get(state, "companies", loan["company_id"])

    state =
      state
      |> put("loans", loan["id"], loan)
      |> put("companies", company["id"], %{company | "profit" => company["profit"] - interest})
      |> Journal.post(company["id"], "loan_interest", [
        {"interest_expense", interest},
        {"loan_interest", -interest}
      ])

    if (scheduled and due <= state.clock_ms) or (not scheduled and loan["interest_accrued"] > 0) do
      bill_due = if scheduled, do: due, else: due - loan["period_ms"]
      id = loan["id"] <> ":" <> to_string(bill_due)
      old = get(state, "loan_installments", id) || %{"principal_due" => 0, "interest_due" => 0}

      principal =
        if scheduled,
          do: min(loan["remaining"] - loan["principal_due"], loan["installment"]),
          else: 0

      bill = %{
        "id" => id,
        "loan_id" => loan["id"],
        "company_id" => company["id"],
        "due_ms" => bill_due,
        "principal_due" => old["principal_due"] + principal,
        "interest_due" => old["interest_due"] + loan["interest_accrued"]
      }

      loan = %{
        loan
        | "principal_due" => loan["principal_due"] + principal,
          "interest_due" => loan["interest_due"] + loan["interest_accrued"],
          "interest_accrued" => 0,
          "overdue_ms" => loan["overdue_ms"] || bill_due,
          "next_due_ms" => if(scheduled, do: due + loan["period_ms"], else: due),
          "periods_left" => max(0, loan["periods_left"] - 1)
      }

      state = state |> put("loan_installments", id, bill) |> put("loans", loan["id"], loan)
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
      entities(state, "operating_bills") |> Map.values() |> Enum.filter(&(&1["company_id"] == id))

    unrecorded = company["unpaid"] - Enum.sum(Enum.map(operations, & &1["remaining"]))

    state =
      if unrecorded > 0,
        do: operating_bill(state, id, unrecorded, company["unpaid_since"] || state.clock_ms),
        else: state

    bills =
      for {bill_id, bill} <- entities(state, "loan_installments"),
          bill["company_id"] == id,
          do: {bill["due_ms"], {"loan", bill_id}}

    bills =
      bills ++
        for {bill_id, bill} <- entities(state, "operating_bills"),
            bill["company_id"] == id and bill["remaining"] > 0,
            do: {bill["due_ms"], {"operations", bill_id}}

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
          |> put("companies", id, %{
            c
            | "cash" => c["cash"] - paid,
              "unpaid" => c["unpaid"] - paid
          })
          |> Journal.post(id, "operating_repayment", [
            {"payables", paid},
            {"cash_available", -paid}
          ])
        else
          row = get(state, "loan_installments", elem(bill, 1))
          pay_loan(state, get(state, "loans", row["loan_id"]), available, row)
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
        {:ok, state, _} = bankrupt(state, get(state, "accounts", company["account_id"]), "forced")
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

  defp pay_loan(state, loan, available, bill \\ nil) do
    interest = min(available, (bill || loan)["interest_due"])
    principal = min(available - interest, (bill || loan)["principal_due"])

    state =
      if bill do
        bill = %{
          bill
          | "principal_due" => bill["principal_due"] - principal,
            "interest_due" => bill["interest_due"] - interest
        }

        if bill["principal_due"] + bill["interest_due"] == 0,
          do: delete(state, "loan_installments", bill["id"]),
          else: put(state, "loan_installments", bill["id"], bill)
      else
        Enum.reduce(entities(state, "loan_installments"), state, fn {id, bill}, state ->
          if bill["loan_id"] == loan["id"],
            do: delete(state, "loan_installments", id),
            else: state
        end)
      end

    c = get(state, "companies", loan["company_id"])

    loan = %{
      loan
      | "interest_due" => loan["interest_due"] - interest,
        "principal_due" => loan["principal_due"] - principal,
        "remaining" => loan["remaining"] - principal
    }

    loan = %{
      loan
      | "status" =>
          if(loan["remaining"] == 0 and loan["interest_due"] == 0, do: "repaid", else: "open"),
        "overdue_ms" =>
          if(loan["principal_due"] + loan["interest_due"] > 0, do: loan["overdue_ms"])
    }

    state
    |> put("loans", loan["id"], loan)
    |> put("companies", c["id"], %{c | "cash" => c["cash"] - interest - principal})
    |> Journal.post(c["id"], "loan_repayment", [
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

  def bankrupt(state, account, reason \\ "voluntary") do
    company = get(state, "companies", account["company_id"])

    cond do
      is_nil(company) or company["account_id"] != account["id"] or company["bankruptcy_ms"] != nil ->
        {:error, :finance_no_company}

      reason == "voluntary" and not can_declare_bankruptcy?(state, account) ->
        {:error, :bankruptcy_cash_covers_debts}

      true ->
        debt =
          Enum.sum(
            for loan <- loans(state, company["id"]),
                do: loan["remaining"] + loan["interest_due"] + loan["interest_accrued"]
          )

        state = Guarantees.default(state, account, debt)
        # A sponsor may itself be the bankrupt company; refresh after refunds.
        company = get(state, "companies", company["id"])

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
            |> Journal.post(company["id"], "bankruptcy_debt", [
              {"loan_principal", loan["remaining"]},
              {"loan_interest", loan["interest_due"] + loan["interest_accrued"]},
              {"receivership",
               -loan["remaining"] - loan["interest_due"] - loan["interest_accrued"]}
            ])
          end)

        state =
          Enum.reduce(
            [
              "route_rules",
              "route_stops",
              "ship_routes",
              "ship_instructions",
              "visit_plans",
              "operating_bills",
              "loan_installments"
            ],
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
            |> Map.put("unpaid", 0)
          )
          |> put("accounts", account["id"], %{
            account
            | "company_id" => nil,
              "bankruptcies" => account["bankruptcies"] + 1
          })
          |> put("bankruptcy_events", company["id"], %{
            "id" => company["id"],
            "company_id" => company["id"],
            "account_id" => account["id"],
            "created_ms" => state.clock_ms,
            "restart_ms" => state.clock_ms + @terms.cooldown_ms,
            "reason" => reason
          })
          |> Journal.post(company["id"], "bankruptcy_payables", [
            {"payables", company["unpaid"]},
            {"receivership", -company["unpaid"]}
          ])
          |> Notices.notice(
            account["id"],
            "bankruptcy:" <> company["id"],
            "#{company["name"]} is in bankruptcy. Its assets remain in receivership. A replacement company becomes available after 20 active-world minutes."
          )

        account = get(state, "accounts", account["id"])

        state =
          if counted(state, account) >= 5 do
            state
            |> put("accounts", account["id"], Map.put(account, "suspended_ms", state.clock_ms))
            |> Notices.notice(
              account["id"],
              "suspension",
              "Account suspended after five recent bankruptcies. Your original sponsor must pledge at least $50,000 to reinstate you."
            )
            |> Notices.notice(
              account["inviter"],
              "suspension:" <> account["id"],
              "An invitee is suspended and needs your cash-backed guarantee. Review sponsor guarantees in the account menu."
            )
          else
            state
          end

        {:ok, state, %{"bankrupt" => company["id"]}}
    end
  end
end
