defmodule TijaraTides.Infrastructure.Persistence.FinancialLedger do
  @moduledoc "Atomic posting and reconciliation; journal history stays in PostgreSQL, not world memory."

  def pending(before, after_state, key) do
    previous = Map.get(before, key, [])
    current = Map.get(after_state, key, [])

    unless Enum.take(current, length(previous)) == previous,
      do: raise(ArgumentError, "Pending event history changed")

    Enum.drop(current, length(previous))
  end

  def write_lots(repo, world, before, after_state) do
    for lot <- pending(before, after_state, :new_lots) do
      repo.query!(
        "INSERT INTO game_cargo_lots(world_id,id,parent_lot_id,good_id,original_quantity_lots,expires_ms,created_ms) VALUES($1,$2,$3,$4,$5,$6,$7)",
        [
          world,
          lot["id"],
          lot["parent_lot_id"],
          lot["good"],
          lot["quantity"],
          lot["expires_ms"],
          lot["created_ms"]
        ]
      )
    end
  end

  def post(repo, world, before, after_state, receipt) do
    for event <- pending(before, after_state, :journal) do
      {accounts, amounts} = Enum.unzip(event.entries)
      request = if receipt, do: elem(receipt, 1)

      repo.query!("SELECT post_game_journal($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)", [
        world,
        event.company,
        event.kind,
        event.clock_ms,
        after_state.revision,
        request,
        event.ship,
        event.good,
        accounts,
        amounts
      ])
    end
  end

  def verify(repo, world) do
    # Bounded by company/account count, rather than the growing journal history.
    rows =
      repo.query!(
        """
        SELECT c.id FROM game_companies c
        LEFT JOIN LATERAL (
          SELECT coalesce(sum(balance_cents) FILTER(WHERE account_code IN ('cash_available','cash_reserved')),0) AS cash,
           coalesce(sum(balance_cents) FILTER(WHERE account_code='cash_reserved'),0) AS reserved,
           -coalesce(sum(balance_cents) FILTER(WHERE account_code='payables'),0) AS unpaid,
           -coalesce(sum(balance_cents) FILTER(WHERE a.category IN ('revenue','expense') OR account_code='opening_profit'),0) AS profit,
           coalesce(sum(balance_cents) FILTER(WHERE account_code='inventory'),0) AS inventory,
           coalesce(sum(balance_cents) FILTER(WHERE account_code='fleet'),0) AS fleet,
           coalesce(sum(balance_cents) FILTER(WHERE account_code='guarantee_escrow'),0) AS guarantees,
           -coalesce(sum(balance_cents) FILTER(WHERE account_code='loan_principal'),0) AS debt,
           -coalesce(sum(balance_cents) FILTER(WHERE account_code='loan_interest'),0) AS interest
          FROM game_ledger_balances b JOIN game_ledger_accounts a ON a.code=b.account_code WHERE b.world_id=c.world_id AND b.company_id=c.id
        ) b ON true
        WHERE c.world_id=$1 AND (c.cash_cents<>b.cash OR c.reserved_cents<>b.reserved OR c.unpaid_cents<>b.unpaid OR c.profit_cents<>b.profit
         OR b.guarantees<>(SELECT coalesce(sum(amount),0) FROM game_guarantees g WHERE g.world_id=c.world_id AND g.company_id=c.id AND g.status='pledged')
         OR c.unpaid_cents<>(SELECT coalesce(sum(remaining),0) FROM game_operating_bills o WHERE o.world_id=c.world_id AND o.company_id=c.id)
         OR EXISTS (SELECT 1 FROM game_loans l WHERE l.world_id=c.world_id AND l.company_id=c.id AND (l.principal_due<>(SELECT coalesce(sum(i.principal_due),0) FROM game_loan_installments i WHERE i.world_id=l.world_id AND i.loan_id=l.id) OR l.interest_due<>(SELECT coalesce(sum(i.interest_due),0) FROM game_loan_installments i WHERE i.world_id=l.world_id AND i.loan_id=l.id)))
         OR b.debt<>(SELECT coalesce(sum(remaining),0) FROM game_loans l WHERE l.world_id=c.world_id AND l.company_id=c.id)
         OR b.interest<>(SELECT coalesce(sum(interest_due + interest_accrued),0) FROM game_loans l WHERE l.world_id=c.world_id AND l.company_id=c.id)
         OR b.inventory<>(SELECT coalesce(sum(h.quantity_lots*h.unit_cost_cents),0) FROM game_cargo_holdings h JOIN game_ships s ON s.world_id=h.world_id AND s.id=h.ship_id WHERE s.world_id=c.world_id AND s.company_id=c.id)
         OR b.fleet<>(SELECT coalesce(sum(book_value_cents),0) FROM game_ships s WHERE s.world_id=c.world_id AND s.company_id=c.id))
        """,
        [world]
      ).rows

    unless rows == [], do: raise(ArgumentError, "Company balances do not reconcile with journal")
    :ok
  end

  def audit(repo, world) do
    # Startup checks the materialized ledger totals against immutable postings.
    rows =
      repo.query!(
        """
        WITH actual AS (
          SELECT t.world_id,t.company_id,e.account_code,sum(e.amount_cents) AS amount
          FROM game_journal_transactions t JOIN game_journal_entries e ON e.transaction_id=t.id
          WHERE t.world_id=$1 AND t.sealed GROUP BY t.world_id,t.company_id,e.account_code
        )
        SELECT 1 FROM actual a FULL JOIN (SELECT * FROM game_ledger_balances WHERE world_id=$1) b
          USING(world_id,company_id,account_code)
        WHERE coalesce(a.amount,0)<>coalesce(b.balance_cents,0) LIMIT 1
        """,
        [world]
      ).rows

    unless rows == [], do: raise(ArgumentError, "Ledger totals disagree with journal history")
    verify(repo, world)
  end
end
