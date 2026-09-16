defmodule TijaraTides.Domain.CompanyFinanceWorld do
  @moduledoc "World loading, row persistence and cross-root coordination for CompanyFinance."
  import TijaraTides.Domain.State
  alias TijaraTides.Domain.{Journal, Notices}
  alias __MODULE__.Guarantees

  alias TijaraTides.Domain.CompanyFinance.{
    Loan,
    Installment,
    OperatingBill,
    Guarantee
  }

  alias TijaraTides.Domain.CompanyFinance
  alias TijaraTides.Domain.CompanyFinance.Rows
  defdelegate terms(), to: CompanyFinance
  defdelegate available(finance), to: CompanyFinance
  defp decode_child("loans", row), do: Loan.from_row(row)
  defp decode_child("loan_installments", row), do: Installment.from_row(row)
  defp decode_child("operating_bills", row), do: OperatingBill.from_row(row)
  defp decode_child("guarantees", row), do: Guarantee.from_row(row)
  defp encode_child(%Loan{} = child), do: Loan.to_row(child)
  defp encode_child(%Installment{} = child), do: Installment.to_row(child)
  defp encode_child(%OperatingBill{} = child), do: OperatingBill.to_row(child)
  defp encode_child(%Guarantee{} = child), do: Guarantee.to_row(child)

  # The one declaration of which struct field holds which owned entity kind.
  # Loading and saving the aggregate derive their pairing here.
  @owned [
    loans: "loans",
    installments: "loan_installments",
    bills: "operating_bills",
    pledges: "guarantees"
  ]

  @doc """
  Load the aggregate: the company, the loans it still owes on, and the other children.

  A settled loan is history and no invariant here depends on it, but a command may still
  name one — repaying twice must stay idempotent rather than report an unknown loan — so
  the loans an operation addresses are loaded alongside the open ones. Children are
  written back from declared mutations rather than by diffing what was loaded, so a
  narrower load drops no row.
  """
  def fetch(state, company_id, addressed \\ []) do
    Enum.reduce(@owned, Rows.decode(get(state, "companies", company_id)), fn {field, kind},
                                                                             finance ->
      Map.put(
        finance,
        field,
        Enum.map(children(state, kind, company_id, addressed), &decode_child(kind, &1))
      )
    end)
  end

  defp children(state, "loans", company_id, addressed) do
    settled =
      addressed
      |> Enum.map(&get(state, "loans", &1))
      |> Enum.filter(&(&1 && &1["company_id"] == company_id && &1["status"] != "open"))

    owned(state, "loans", "open_company_id", company_id) ++ settled
  end

  defp children(state, kind, company_id, _addressed),
    do: owned(state, kind, "company_id", company_id)

  def open(state, row) do
    finance = Rows.decode(row)

    CompanyFinance.open(finance, get(state, "companies", finance.id) != nil)

    put(state, "companies", finance.id, row)
  end

  def post(state, company_id, kind, entries, context \\ %{}) do
    row = get(state, "companies", company_id) || raise(ArgumentError, "Missing financial owner")
    finance = row |> Rows.decode() |> CompanyFinance.apply_entries(entries)

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
    company = get(state, "companies", company_id) |> Rows.decode()
    maintenance = Map.get(effects, :maintenance, 0)
    upkeep = effects.crew + maintenance
    paid = min(upkeep, available(company))

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
        {"maintenance_expense", maintenance},
        {"cash_available", -paid},
        {"payables", -(upkeep - paid)},
        {"spoilage_expense", effects.spoilage},
        {"inventory", -effects.spoilage}
      ],
      %{ship: ship_id}
    )
    |> operating_bill(company_id, upkeep - paid, state.clock_ms)
  end

  @terms CompanyFinance.terms()
  def rate(state, account), do: CompanyFinance.rate(counted(state, account))
  def credit_limit(state, account), do: CompanyFinance.credit_limit(counted(state, account))

  defdelegate history(state, account), to: TijaraTides.Domain.AccountWorld
  defdelegate counted(state, account), to: TijaraTides.Domain.AccountWorld
  defdelegate restart_at(state, account), to: TijaraTides.Domain.AccountWorld

  def loans(state, company),
    do:
      owned(state, "loans", "company_id", company)
      |> Enum.sort_by(&{&1["created_ms"], &1["id"]})

  @doc """
  Loans the company is still paying. Every per-command path reads this rather than
  `loans/2`: a settled loan is history, and a company's history is unbounded while the
  loans it owes on are capped at #{8}.
  """
  def open_loans(state, company),
    do:
      owned(state, "loans", "open_company_id", company)
      |> Enum.sort_by(&{&1["created_ms"], &1["id"]})

  def summary(state, account) do
    company = get(state, "companies", account["company_id"])

    open = open_loans(state, account["company_id"])

    # Anything still owed keeps a loan open, so narrowing the sum cannot change it.
    debt = Enum.sum(Enum.map(open, & &1["remaining"]))
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
      Enum.sum(for l <- open, do: l["principal_due"] + l["interest_due"]) +
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
        Enum.map(open, fn loan ->
          loan
          |> Map.put("schedule", schedule(loan))
          |> Map.put("actions", loan_actions(company, loan))
        end)
    }
  end

  def loan_actions(company, loan),
    do: CompanyFinance.loan_actions(if(company, do: Rows.decode(company)), Loan.from_row(loan))

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
    guarantee = Guarantees.active(state, account["id"])

    facts = %{
      account_id: account["id"],
      guarantee_id: if(guarantee, do: guarantee["id"]),
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
             CompanyFinance.loan_transition(
               fetch(state, company["id"], addressed(operation)),
               account["id"],
               operation,
               state.clock_ms
             ) do
        {:ok, save_finances(state, next, effects), result}
      end
    end
  end

  # Loans a command names by identity, which it must see even once they are settled.
  defp addressed({:repay, id}), do: [id]
  defp addressed({:recast, id, _amount}), do: [id]
  defp addressed(_operation), do: []

  def settle_owned(state, id) do
    {finance, effects} = CompanyFinance.settle_finances(fetch(state, id), state.clock_ms)
    {save_finances(state, finance, effects), encode_effects(effects)}
  end

  defp save_finances(state, finance, effects) do
    effects = encode_effects(effects)
    id = finance.id
    state = put(state, "companies", id, Rows.encode(finance))

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
      Notices.notice(
        state,
        notice["account_id"],
        notice_id,
        if(notice["code"], do: {notice["code"], notice["arguments"]}, else: notice["text"])
      )
    end)
  end

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

  def can_declare_bankruptcy?(state, account) do
    company = get(state, "companies", account["company_id"])

    if company && company["account_id"] == account["id"] && is_nil(company["bankruptcy_ms"]) do
      liabilities =
        company["unpaid"] +
          Enum.sum(
            for loan <- open_loans(state, company["id"]),
                do: loan["remaining"] + loan["interest_due"] + loan["interest_accrued"]
          )

      cancellable_orders =
        Enum.sum(
          for o <- owned(state, "exchange_orders", "company_id", company["id"]),
              o["side"] == "buy",
              do: o["quantity"] * o["price"]
        )

      cancellable_bids =
        Enum.sum(
          for b <- TijaraTides.Domain.AuctionWorld.company_bids(state, company["id"]),
              get(state, "auctions", b.auction_id)["status"] == "scheduled",
              do: b.amount
        )

      company["cash"] - company["reserved"] + cancellable_orders + cancellable_bids < liabilities
    else
      false
    end
  end

  def estate_expense(state, company_id, amount, account) do
    company = TijaraTides.Domain.State.get(state, "companies", company_id)
    unless company["bankruptcy_ms"] != nil, do: raise(ArgumentError, "Not an estate")
    paid = min(amount, max(0, company["cash"] - company["reserved"]))

    post(state, company_id, "estate_expense", [
      {account, amount},
      {"cash_available", -paid},
      {"receivership", paid - amount}
    ])
  end

  def close_in_receivership(state, company_id) do
    # Receivership explicitly addresses settled history as well as open loans.
    addressed = Enum.map(loans(state, company_id), & &1["id"])

    {finance, effects} =
      CompanyFinance.close_in_receivership(fetch(state, company_id, addressed), state.clock_ms)

    save_finances(state, finance, effects)
    |> Notices.notice(
      finance.account_id,
      "bankruptcy:" <> company_id,
      {"company.bankrupt", %{"company" => finance.name}}
    )
  end

  defp encode_effects(effects) do
    kinds = Map.new(@owned)

    %{
      effects
      | children:
          Enum.map(effects.children, fn {kind, id, op, child} ->
            {Map.fetch!(kinds, kind), id, op, if(child, do: encode_child(child))}
          end),
        notices:
          Enum.map(effects.notices, fn {id, notice} ->
            {code, arguments} = notice.payload
            {id, %{"account_id" => notice.account_id, "code" => code, "arguments" => arguments}}
          end)
    }
  end
end
