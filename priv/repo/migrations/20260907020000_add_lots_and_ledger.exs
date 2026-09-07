defmodule TijaraTides.Infrastructure.Persistence.Repo.Migrations.AddLotsAndLedger do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE game_worlds ADD COLUMN next_lot_id bigint NOT NULL DEFAULT 1 CHECK(next_lot_id > 0);
    """)

    execute("""
    ALTER TABLE game_ships ADD COLUMN book_value_cents bigint NOT NULL DEFAULT 0 CHECK(book_value_cents >= 0);
    """)

    execute("""
    UPDATE game_ships SET book_value_cents=CASE class_id WHEN 'freighter' THEN 4000000 WHEN 'small_freighter' THEN 3000000 WHEN 'bulk' THEN 5000000 WHEN 'reefer' THEN 5000000 WHEN 'tanker' THEN 5000000 END;
    """)

    execute("""
    CREATE TABLE game_cargo_lots (
     world_id text NOT NULL REFERENCES game_worlds(id), id text NOT NULL,
     parent_lot_id text, good_id text NOT NULL REFERENCES game_cargo_types(id),
     original_quantity_lots bigint NOT NULL CHECK(original_quantity_lots > 0),
     expires_ms bigint CHECK(expires_ms >= 0), created_ms bigint NOT NULL CHECK(created_ms >= 0),
     PRIMARY KEY(world_id,id), CHECK(parent_lot_id IS DISTINCT FROM id),
     FOREIGN KEY(world_id,parent_lot_id) REFERENCES game_cargo_lots(world_id,id)
    );
    """)

    execute("""
    CREATE INDEX ON game_cargo_lots(world_id,parent_lot_id);
    """)

    execute("""
    CREATE TABLE game_cargo_holdings (
     world_id text NOT NULL, lot_id text NOT NULL, ship_id text, market_id text,
     position integer NOT NULL CHECK(position >= 0), quantity_lots bigint NOT NULL CHECK(quantity_lots > 0),
     unit_cost_cents bigint CHECK(unit_cost_cents >= 0),
     PRIMARY KEY(world_id,lot_id),
     CHECK ((ship_id IS NOT NULL)::integer + (market_id IS NOT NULL)::integer = 1),
     CHECK ((ship_id IS NOT NULL) = (unit_cost_cents IS NOT NULL)),
     FOREIGN KEY(world_id,lot_id) REFERENCES game_cargo_lots(world_id,id),
     FOREIGN KEY(world_id,ship_id) REFERENCES game_ships(world_id,id) DEFERRABLE INITIALLY DEFERRED,
     FOREIGN KEY(world_id,market_id) REFERENCES game_markets(world_id,id) DEFERRABLE INITIALLY DEFERRED,
     UNIQUE(world_id,ship_id,position) DEFERRABLE INITIALLY DEFERRED,
     UNIQUE(world_id,market_id,position) DEFERRABLE INITIALLY DEFERRED
    );
    """)

    execute("""
    CREATE TEMP TABLE migrated_lots ON COMMIT DROP AS
    SELECT b.*, 'lot:' || row_number() OVER(PARTITION BY world_id ORDER BY location_kind,owner_id,position) AS lot_id
    FROM (
     SELECT world_id,'ship' AS location_kind,ship_id AS owner_id,position,quantity_lots,unit_cost_cents,good_id,expires_ms FROM game_ship_cargo_batches
     UNION ALL
     SELECT b.world_id,'market',b.market_id,b.position,b.quantity_lots,NULL::bigint,m.good_id,b.expires_ms FROM game_market_stock_batches b JOIN game_markets m ON m.world_id=b.world_id AND m.id=b.market_id
    ) b;
    """)

    execute("""
    INSERT INTO game_cargo_lots(world_id,id,good_id,original_quantity_lots,expires_ms,created_ms)
    SELECT l.world_id,l.lot_id,l.good_id,l.quantity_lots,l.expires_ms,w.clock_ms FROM migrated_lots l JOIN game_worlds w ON w.id=l.world_id;
    """)

    execute("""
    INSERT INTO game_cargo_holdings(world_id,lot_id,ship_id,market_id,position,quantity_lots,unit_cost_cents)
    SELECT world_id,lot_id,CASE WHEN location_kind='ship' THEN owner_id END,CASE WHEN location_kind='market' THEN owner_id END,position,quantity_lots,unit_cost_cents FROM migrated_lots;
    """)

    execute("""
    UPDATE game_worlds w SET next_lot_id=1+(SELECT count(*) FROM migrated_lots l WHERE l.world_id=w.id);
    """)

    execute("""
    DROP TABLE game_ship_cargo_batches,game_market_stock_batches;
    """)

    execute("""
    CREATE TABLE game_ledger_accounts(code text PRIMARY KEY,category text NOT NULL CHECK(category IN ('asset','liability','equity','revenue','expense')));
    """)

    execute("""
    INSERT INTO game_ledger_accounts VALUES
    ('cash_available','asset'),('cash_reserved','asset'),('inventory','asset'),('fleet','asset'),('payables','liability'),('capital','equity'),('opening_profit','equity'),('sales_revenue','revenue'),('cost_of_goods','expense'),('handling_expense','expense'),('cleaning_expense','expense'),('fuel_expense','expense'),('crew_expense','expense'),('spoilage_expense','expense'),('canal_expense','expense');
    """)

    execute("""
    CREATE TABLE game_journal_transactions(
     id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     world_id text NOT NULL, company_id text NOT NULL, kind text NOT NULL,
     clock_ms bigint NOT NULL CHECK(clock_ms>=0), world_revision bigint NOT NULL,
     request_id text, ship_id text, good_id text REFERENCES game_cargo_types(id),
     sealed boolean NOT NULL DEFAULT false,
     UNIQUE(world_id,id),
     FOREIGN KEY(world_id,company_id) REFERENCES game_companies(world_id,id) DEFERRABLE INITIALLY DEFERRED,
     FOREIGN KEY(world_id,ship_id) REFERENCES game_ships(world_id,id) DEFERRABLE INITIALLY DEFERRED
    );
    """)

    execute("""
    CREATE INDEX ON game_journal_transactions(world_id,company_id,id);
    """)

    execute("""
    CREATE INDEX ON game_journal_transactions(world_id,request_id) WHERE request_id IS NOT NULL;
    """)

    execute("""
    CREATE TABLE game_journal_entries(
     transaction_id bigint NOT NULL REFERENCES game_journal_transactions(id),
     position integer NOT NULL CHECK(position>=0),account_code text NOT NULL REFERENCES game_ledger_accounts(code),
     amount_cents bigint NOT NULL CHECK(amount_cents<>0),PRIMARY KEY(transaction_id,position)
    );
    """)

    execute("""
    CREATE TABLE game_ledger_balances(
     world_id text NOT NULL,company_id text NOT NULL,account_code text NOT NULL REFERENCES game_ledger_accounts(code),
     balance_cents bigint NOT NULL,PRIMARY KEY(world_id,company_id,account_code),
     FOREIGN KEY(world_id,company_id) REFERENCES game_companies(world_id,id) DEFERRABLE INITIALLY DEFERRED
    );
    """)

    execute("""
    CREATE FUNCTION reject_immutable_change() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN RAISE EXCEPTION 'Posted journals and lot identities are immutable'; END $$;
    """)

    execute("""
    CREATE TRIGGER immutable_lots BEFORE UPDATE OR DELETE ON game_cargo_lots FOR EACH ROW EXECUTE FUNCTION reject_immutable_change();
    """)

    execute("""
    CREATE TRIGGER immutable_entries BEFORE UPDATE OR DELETE ON game_journal_entries FOR EACH ROW EXECUTE FUNCTION reject_immutable_change();
    """)

    execute("""
    CREATE FUNCTION journal_entry_insert() RETURNS trigger LANGUAGE plpgsql AS $$
    DECLARE posted boolean;
    BEGIN
     SELECT sealed INTO STRICT posted FROM game_journal_transactions WHERE id=NEW.transaction_id FOR UPDATE;
     IF posted THEN RAISE EXCEPTION 'Cannot append to posted journal'; END IF;
     RETURN NEW;
    END $$;
    """)

    execute("""
    CREATE TRIGGER journal_entry_insert BEFORE INSERT ON game_journal_entries FOR EACH ROW EXECUTE FUNCTION journal_entry_insert();
    """)

    execute("""
    CREATE FUNCTION seal_journal() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
     IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Journal is append-only'; END IF;
     IF OLD.sealed OR NOT NEW.sealed OR (to_jsonb(OLD)-'sealed') IS DISTINCT FROM (to_jsonb(NEW)-'sealed') THEN RAISE EXCEPTION 'Journal is append-only'; END IF;
     IF (SELECT count(*)<2 OR sum(amount_cents)<>0 FROM game_journal_entries WHERE transaction_id=NEW.id) THEN RAISE EXCEPTION 'Journal must balance'; END IF;
     INSERT INTO game_ledger_balances(world_id,company_id,account_code,balance_cents)
     SELECT NEW.world_id,NEW.company_id,account_code,sum(amount_cents) FROM game_journal_entries WHERE transaction_id=NEW.id GROUP BY account_code
     ON CONFLICT(world_id,company_id,account_code) DO UPDATE SET balance_cents=game_ledger_balances.balance_cents+EXCLUDED.balance_cents;
     RETURN NEW;
    END $$;
    """)

    execute("""
    CREATE TRIGGER seal_journal BEFORE UPDATE OR DELETE ON game_journal_transactions FOR EACH ROW EXECUTE FUNCTION seal_journal();
    """)

    execute("""
    CREATE FUNCTION require_posted_journal() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
     IF NOT EXISTS(SELECT 1 FROM game_journal_transactions WHERE id=NEW.id AND sealed) THEN RAISE EXCEPTION 'Unposted journal at commit'; END IF;
     RETURN NULL;
    END $$;
    """)

    execute("""
    CREATE CONSTRAINT TRIGGER require_posted_journal AFTER INSERT ON game_journal_transactions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION require_posted_journal();
    """)

    execute("""
    CREATE FUNCTION new_journal_unsealed() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN IF NEW.sealed THEN RAISE EXCEPTION 'New journals must start unposted'; END IF; RETURN NEW; END $$;
    """)

    execute("""
    CREATE TRIGGER new_journal_unsealed BEFORE INSERT ON game_journal_transactions FOR EACH ROW EXECUTE FUNCTION new_journal_unsealed();
    """)

    execute("""
    CREATE FUNCTION post_game_journal(p_world text,p_company text,p_kind text,p_clock bigint,p_revision bigint,p_request text,p_ship text,p_good text,p_accounts text[],p_amounts bigint[]) RETURNS bigint LANGUAGE plpgsql AS $$
    DECLARE tx bigint;
    BEGIN
     IF cardinality(p_accounts) IS DISTINCT FROM cardinality(p_amounts) THEN RAISE EXCEPTION 'Mismatched journal lines'; END IF;
     IF NOT EXISTS(SELECT 1 FROM unnest(p_amounts) amount WHERE amount<>0) THEN RETURN NULL; END IF;
     INSERT INTO game_journal_transactions(world_id,company_id,kind,clock_ms,world_revision,request_id,ship_id,good_id)
     VALUES(p_world,p_company,p_kind,p_clock,p_revision,p_request,p_ship,p_good) RETURNING id INTO tx;
     INSERT INTO game_journal_entries(transaction_id,position,account_code,amount_cents)
     SELECT tx,(ordinality-1)::integer,account,amount FROM unnest(p_accounts,p_amounts) WITH ORDINALITY AS lines(account,amount,ordinality) WHERE amount<>0;
     UPDATE game_journal_transactions SET sealed=true WHERE id=tx;
     RETURN tx;
    END $$;
    """)

    execute("""
    DO $$
    DECLARE c record; stock bigint; fleet bigint; capital bigint;
    BEGIN
     FOR c IN SELECT companyrow.*,w.clock_ms,w.revision FROM game_companies companyrow JOIN game_worlds w ON w.id=companyrow.world_id LOOP
      SELECT coalesce(sum(h.quantity_lots*h.unit_cost_cents),0) INTO stock FROM game_cargo_holdings h JOIN game_ships s ON s.world_id=h.world_id AND s.id=h.ship_id WHERE s.world_id=c.world_id AND s.company_id=c.id;
      SELECT coalesce(sum(book_value_cents),0) INTO fleet FROM game_ships WHERE world_id=c.world_id AND company_id=c.id;
      capital := c.cash_cents + stock + fleet - c.unpaid_cents - c.profit_cents;
      PERFORM post_game_journal(c.world_id,c.id,'opening_balance',c.clock_ms,c.revision,NULL,NULL,NULL,
       ARRAY['cash_available','cash_reserved','inventory','fleet','payables','opening_profit','capital'],
       ARRAY[c.cash_cents-c.reserved_cents,c.reserved_cents,stock,fleet,-c.unpaid_cents,-c.profit_cents,-capital]);
     END LOOP;
    END $$;
    """)

    execute("""
    CREATE VIEW game_ship_cargo_batches AS SELECT h.world_id,h.ship_id,h.position,h.quantity_lots,l.expires_ms,l.good_id,h.unit_cost_cents,h.lot_id FROM game_cargo_holdings h JOIN game_cargo_lots l ON l.world_id=h.world_id AND l.id=h.lot_id WHERE h.ship_id IS NOT NULL;
    """)

    execute("""
    CREATE VIEW game_market_stock_batches AS SELECT h.world_id,h.market_id,h.position,h.quantity_lots,l.expires_ms,h.lot_id FROM game_cargo_holdings h JOIN game_cargo_lots l ON l.world_id=h.world_id AND l.id=h.lot_id WHERE h.market_id IS NOT NULL;
    """)

    execute("""
    CREATE FUNCTION validate_cargo_holding() RETURNS trigger LANGUAGE plpgsql AS $$
    DECLARE lot record; market_good text;
    BEGIN
     SELECT * INTO STRICT lot FROM game_cargo_lots WHERE world_id=NEW.world_id AND id=NEW.lot_id;
     IF NEW.quantity_lots<>lot.original_quantity_lots THEN RAISE EXCEPTION 'Split lots instead of changing their quantity'; END IF;
     IF EXISTS(SELECT 1 FROM game_cargo_lots WHERE world_id=NEW.world_id AND parent_lot_id=NEW.lot_id) THEN RAISE EXCEPTION 'A split parent cannot be held'; END IF;
     IF NEW.market_id IS NOT NULL THEN
      SELECT good_id INTO STRICT market_good FROM game_markets WHERE world_id=NEW.world_id AND id=NEW.market_id;
      IF market_good<>lot.good_id THEN RAISE EXCEPTION 'Wrong cargo for market'; END IF;
     END IF;
     RETURN NEW;
    END $$;
    """)

    execute("""
    CREATE TRIGGER validate_cargo_holding BEFORE INSERT OR UPDATE ON game_cargo_holdings FOR EACH ROW EXECUTE FUNCTION validate_cargo_holding();
    """)

    execute("""
    CREATE FUNCTION validate_lot_split() RETURNS trigger LANGUAGE plpgsql AS $$
    DECLARE parent record;
    BEGIN
     IF NEW.parent_lot_id IS NOT NULL THEN
      SELECT * INTO STRICT parent FROM game_cargo_lots WHERE world_id=NEW.world_id AND id=NEW.parent_lot_id;
      IF parent.good_id<>NEW.good_id OR parent.expires_ms IS DISTINCT FROM NEW.expires_ms THEN RAISE EXCEPTION 'Split identity mismatch'; END IF;
      IF EXISTS(SELECT 1 FROM game_cargo_holdings WHERE world_id=NEW.world_id AND lot_id=NEW.parent_lot_id) THEN RAISE EXCEPTION 'Split parent still held'; END IF;
      IF (SELECT sum(original_quantity_lots) FROM game_cargo_lots WHERE world_id=NEW.world_id AND parent_lot_id=NEW.parent_lot_id)<>parent.original_quantity_lots THEN RAISE EXCEPTION 'Split quantities do not conserve cargo'; END IF;
     END IF;
     RETURN NULL;
    END $$;
    """)

    execute("""
    CREATE CONSTRAINT TRIGGER validate_lot_split AFTER INSERT ON game_cargo_lots DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION validate_lot_split();
    """)

    execute("""
    CREATE FUNCTION ledger_balance_write() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      IF pg_trigger_depth() < 2 THEN RAISE EXCEPTION 'Ledger balances are maintained by journal posting'; END IF;
      RETURN NEW;
    END $$;
    """)

    execute(
      "CREATE TRIGGER ledger_balance_write BEFORE INSERT OR UPDATE OR DELETE ON game_ledger_balances FOR EACH ROW EXECUTE FUNCTION ledger_balance_write()"
    )
  end

  def down do
    raise "Restore the pre-migration backup; ledger history and permanent lot identities must not be discarded."
  end
end
