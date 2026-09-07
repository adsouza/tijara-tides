defmodule TijaraTides.Infrastructure.Persistence.Repo.Migrations.NormalizeGameStorage do
  use Ecto.Migration

  def up do
    execute("""
    DO $$ BEGIN IF EXISTS (SELECT 1 FROM game_entities WHERE kind NOT IN ('accounts','companies','ships','markets','sessions','invitations','notices')) THEN RAISE EXCEPTION 'Unknown legacy entity kind; refusing lossy migration'; END IF; END $$;
    """)

    execute("""
    CREATE TABLE game_ports (id text PRIMARY KEY, display_name text NOT NULL);
    """)

    execute("""
    INSERT INTO game_ports(id,display_name) VALUES ('Abu Dhabi','Abu Dhabi'),('Antwerp','Antwerp'),('Athens','Athens'),('Busan','Busan'),('Colombo','Colombo'),('Colón','Colón'),('Dubai','Dubai'),('Guangzhou','Guangzhou'),('Hamburg','Hamburg'),('Ho Chi Minh City','Ho Chi Minh City'),('Hong Kong','Hong Kong'),('Houston','Houston'),('Jakarta','Jakarta'),('Los Angeles','Los Angeles'),('Manila','Manila'),('Mumbai','Mumbai'),('New York City','New York City'),('Rotterdam','Rotterdam'),('Shanghai','Shanghai'),('Shenzhen','Shenzhen'),('Singapore','Singapore'),('São Paulo','São Paulo'),('Tangier','Tangier'),('Tokyo','Tokyo'),('Valencia','Valencia');
    """)

    execute("""
    CREATE TABLE game_cargo_types (id text PRIMARY KEY, display_name text NOT NULL);
    """)

    execute("""
    INSERT INTO game_cargo_types(id,display_name) VALUES ('Agricultural machinery','Agricultural machinery'),('Appliances','Appliances'),('Construction equipment','Construction equipment'),('Copper scrap','Copper scrap'),('Crude oil','Crude oil'),('Designer clothing','Designer clothing'),('Electronics','Electronics'),('Everyday clothing','Everyday clothing'),('Fruit','Fruit'),('Grain','Grain'),('Iron ore','Iron ore'),('Jewelry','Jewelry'),('Lumber','Lumber'),('Meat','Meat'),('Recovered plastics','Recovered plastics'),('Refined fuel','Refined fuel'),('Scrap aluminium','Aluminium scrap'),('Seafood','Seafood'),('Spices','Spices'),('Turbines','Turbines'),('Vegetable oil','Vegetable oil'),('Whisky','Whisky');
    """)

    execute("""
    CREATE TABLE game_ship_classes (id text PRIMARY KEY, display_name text NOT NULL);
    """)

    execute("""
    INSERT INTO game_ship_classes(id,display_name) VALUES ('freighter','Balanced freighter'),('small_freighter','Small freighter'),('bulk','Bulk carrier'),('reefer','Small refrigerated ship'),('tanker','Small tanker');
    """)

    execute("""
    CREATE TABLE game_accounts (
      world_id text NOT NULL REFERENCES game_worlds(id) ON DELETE CASCADE,
      id text NOT NULL,
      company_id text,
      inviter_account_id text,
      bankruptcies bigint NOT NULL,
      invite_quota bigint NOT NULL,
      created_ms bigint NOT NULL,
      PRIMARY KEY(world_id,id),
      CHECK (bankruptcies >= 0),
      CHECK (invite_quota >= 0),
      CHECK (created_ms >= 0)
    );
    """)

    execute("""
    CREATE TABLE game_companies (
      world_id text NOT NULL REFERENCES game_worlds(id) ON DELETE CASCADE,
      id text NOT NULL,
      account_id text NOT NULL,
      name text NOT NULL,
      home_port_id text NOT NULL,
      cash_cents bigint NOT NULL,
      reserved_cents bigint NOT NULL,
      profit_cents bigint NOT NULL,
      unpaid_cents bigint NOT NULL,
      created_ms bigint NOT NULL,
      last_invite_year bigint NOT NULL,
      PRIMARY KEY(world_id,id),
      CHECK (cash_cents >= 0),
      CHECK (reserved_cents BETWEEN 0 AND cash_cents),
      CHECK (unpaid_cents >= 0),
      CHECK (created_ms >= 0),
      CHECK (last_invite_year >= 0),
      CHECK (length(trim(name)) > 0),
      UNIQUE(world_id,id,account_id)
    );
    """)

    execute("""
    CREATE TABLE game_ships (
      world_id text NOT NULL REFERENCES game_worlds(id) ON DELETE CASCADE,
      id text NOT NULL,
      company_id text NOT NULL,
      name text NOT NULL,
      class_id text NOT NULL,
      port_id text NOT NULL,
      status text NOT NULL,
      arrive_ms bigint,
      destination_port_id text,
      depart_ms bigint,
      fuel_total_cents bigint NOT NULL,
      fuel_burned_cents bigint NOT NULL,
      crew_remainder bigint NOT NULL,
      last_cost_ms bigint NOT NULL,
      last_liquid_good_id text,
      voyage_speedup bigint,
      PRIMARY KEY(world_id,id),
      CHECK (status IN ('docked','loading','unloading','sailing')),
      CHECK (fuel_total_cents >= 0),
      CHECK (fuel_burned_cents BETWEEN 0 AND fuel_total_cents),
      CHECK (crew_remainder BETWEEN 0 AND 119999),
      CHECK (last_cost_ms >= 0),
      CHECK (voyage_speedup IS NULL OR voyage_speedup > 0),
      CHECK (status <> 'sailing' OR (destination_port_id IS NOT NULL AND depart_ms IS NOT NULL AND arrive_ms > depart_ms)),
      CHECK (status <> 'docked' OR (destination_port_id IS NULL AND arrive_ms IS NULL AND depart_ms IS NULL))
    );
    """)

    execute("""
    CREATE TABLE game_markets (
      world_id text NOT NULL REFERENCES game_worlds(id) ON DELETE CASCADE,
      id text NOT NULL,
      port_id text NOT NULL,
      good_id text NOT NULL,
      merchant boolean NOT NULL,
      seller boolean NOT NULL,
      buyer boolean NOT NULL,
      stock_lots bigint NOT NULL,
      demand_lots bigint NOT NULL,
      budget_cents bigint NOT NULL,
      last_production_ms bigint NOT NULL,
      PRIMARY KEY(world_id,id),
      CHECK (stock_lots >= 0),
      CHECK (demand_lots >= 0),
      CHECK (budget_cents >= 0),
      CHECK (last_production_ms >= 0),
      UNIQUE(world_id,port_id,good_id)
    );
    """)

    execute("""
    CREATE TABLE game_sessions (
      world_id text NOT NULL REFERENCES game_worlds(id) ON DELETE CASCADE,
      id text NOT NULL,
      account_id text NOT NULL,
      expires_at_ms bigint NOT NULL,
      PRIMARY KEY(world_id,id),
      CHECK (expires_at_ms >= 0)
    );
    """)

    execute("""
    CREATE TABLE game_invitations (
      world_id text NOT NULL REFERENCES game_worlds(id) ON DELETE CASCADE,
      id text NOT NULL,
      inviter_account_id text,
      expires_ms bigint NOT NULL,
      status text NOT NULL,
      seed boolean NOT NULL,
      invitee_account_id text,
      PRIMARY KEY(world_id,id),
      CHECK (expires_ms >= 0),
      CHECK (status IN ('issued','redeemed','expired')),
      CHECK ((status = 'redeemed') = (invitee_account_id IS NOT NULL)),
      CHECK (seed = (inviter_account_id IS NULL))
    );
    """)

    execute("""
    CREATE TABLE game_notices (
      world_id text NOT NULL REFERENCES game_worlds(id) ON DELETE CASCADE,
      id text NOT NULL,
      account_id text NOT NULL,
      message text NOT NULL,
      clock_ms bigint NOT NULL,
      PRIMARY KEY(world_id,id),
      CHECK (clock_ms >= 0)
    );
    """)

    execute("""
    ALTER TABLE game_accounts ADD FOREIGN KEY(world_id,inviter_account_id) REFERENCES game_accounts(world_id,id) DEFERRABLE INITIALLY DEFERRED;
    """)

    execute("""
    CREATE INDEX ON game_accounts(world_id,inviter_account_id);
    """)

    execute("""
    ALTER TABLE game_accounts ADD FOREIGN KEY(world_id,company_id) REFERENCES game_companies(world_id,id) DEFERRABLE INITIALLY DEFERRED;
    """)

    execute("""
    CREATE INDEX ON game_accounts(world_id,company_id);
    """)

    execute("""
    ALTER TABLE game_companies ADD FOREIGN KEY(world_id,account_id) REFERENCES game_accounts(world_id,id) DEFERRABLE INITIALLY DEFERRED;
    """)

    execute("""
    CREATE INDEX ON game_companies(world_id,account_id);
    """)

    execute("""
    ALTER TABLE game_ships ADD FOREIGN KEY(world_id,company_id) REFERENCES game_companies(world_id,id) DEFERRABLE INITIALLY DEFERRED;
    """)

    execute("""
    CREATE INDEX ON game_ships(world_id,company_id);
    """)

    execute("""
    ALTER TABLE game_sessions ADD FOREIGN KEY(world_id,account_id) REFERENCES game_accounts(world_id,id) DEFERRABLE INITIALLY DEFERRED;
    """)

    execute("""
    CREATE INDEX ON game_sessions(world_id,account_id);
    """)

    execute("""
    ALTER TABLE game_invitations ADD FOREIGN KEY(world_id,inviter_account_id) REFERENCES game_accounts(world_id,id) DEFERRABLE INITIALLY DEFERRED;
    """)

    execute("""
    CREATE INDEX ON game_invitations(world_id,inviter_account_id);
    """)

    execute("""
    ALTER TABLE game_invitations ADD FOREIGN KEY(world_id,invitee_account_id) REFERENCES game_accounts(world_id,id) DEFERRABLE INITIALLY DEFERRED;
    """)

    execute("""
    CREATE INDEX ON game_invitations(world_id,invitee_account_id);
    """)

    execute("""
    ALTER TABLE game_notices ADD FOREIGN KEY(world_id,account_id) REFERENCES game_accounts(world_id,id) DEFERRABLE INITIALLY DEFERRED;
    """)

    execute("""
    CREATE INDEX ON game_notices(world_id,account_id);
    """)

    execute("""
    ALTER TABLE game_accounts ADD FOREIGN KEY(world_id,company_id,id) REFERENCES game_companies(world_id,id,account_id) DEFERRABLE INITIALLY DEFERRED;
    """)

    execute("""
    ALTER TABLE game_companies ADD FOREIGN KEY(home_port_id) REFERENCES game_ports(id);
    """)

    execute("""
    ALTER TABLE game_ships ADD FOREIGN KEY(class_id) REFERENCES game_ship_classes(id);
    """)

    execute("""
    ALTER TABLE game_ships ADD FOREIGN KEY(port_id) REFERENCES game_ports(id);
    """)

    execute("""
    ALTER TABLE game_ships ADD FOREIGN KEY(destination_port_id) REFERENCES game_ports(id);
    """)

    execute("""
    ALTER TABLE game_ships ADD FOREIGN KEY(last_liquid_good_id) REFERENCES game_cargo_types(id);
    """)

    execute("""
    ALTER TABLE game_markets ADD FOREIGN KEY(port_id) REFERENCES game_ports(id);
    """)

    execute("""
    ALTER TABLE game_markets ADD FOREIGN KEY(good_id) REFERENCES game_cargo_types(id);
    """)

    execute("""
    CREATE TABLE game_ship_cargo_batches (world_id text NOT NULL, ship_id text NOT NULL, position integer NOT NULL CHECK(position >= 0), quantity_lots bigint NOT NULL CHECK(quantity_lots > 0), expires_ms bigint CHECK(expires_ms >= 0), good_id text NOT NULL REFERENCES game_cargo_types(id), unit_cost_cents bigint NOT NULL CHECK(unit_cost_cents >= 0), PRIMARY KEY(world_id,ship_id,position), FOREIGN KEY(world_id,ship_id) REFERENCES game_ships(world_id,id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED);
    """)

    execute("""
    CREATE TABLE game_market_stock_batches (world_id text NOT NULL, market_id text NOT NULL, position integer NOT NULL CHECK(position >= 0), quantity_lots bigint NOT NULL CHECK(quantity_lots > 0), expires_ms bigint CHECK(expires_ms >= 0), PRIMARY KEY(world_id,market_id,position), FOREIGN KEY(world_id,market_id) REFERENCES game_markets(world_id,id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED);
    """)

    execute("""
    CREATE INDEX ON game_ship_cargo_batches(world_id,good_id);
    """)

    execute("""
    CREATE INDEX ON game_ships(world_id,port_id,status);
    """)

    execute("""
    CREATE INDEX ON game_markets(world_id,good_id);
    """)

    execute("""
    CREATE INDEX ON game_invitations(world_id,status,expires_ms);
    """)

    execute("""
    DO $$ BEGIN IF EXISTS (SELECT 1 FROM game_entities WHERE kind='accounts' AND data - ARRAY['id','company_id','inviter','bankruptcies','invite_quota','created_ms']::text[] <> '{}'::jsonb) THEN RAISE EXCEPTION 'Unknown fields in legacy accounts; refusing lossy migration'; END IF; END $$;
    """)

    execute("""
    DO $$ BEGIN IF EXISTS (SELECT 1 FROM game_entities WHERE kind='accounts' AND (data->>'id') IS DISTINCT FROM id) THEN RAISE EXCEPTION 'Legacy accounts ID mismatch'; END IF; END $$;
    """)

    execute("""
    INSERT INTO game_accounts (world_id,id,company_id,inviter_account_id,bankruptcies,invite_quota,created_ms) SELECT world_id,id,(data->>'company_id')::text,(data->>'inviter')::text,(data->>'bankruptcies')::bigint,(data->>'invite_quota')::bigint,(data->>'created_ms')::bigint FROM game_entities WHERE kind='accounts';
    """)

    execute("""
    DO $$ BEGIN IF EXISTS (SELECT 1 FROM game_entities WHERE kind='companies' AND data - ARRAY['id','account_id','name','home','cash','reserved','profit','unpaid','created_ms','last_invite_year']::text[] <> '{}'::jsonb) THEN RAISE EXCEPTION 'Unknown fields in legacy companies; refusing lossy migration'; END IF; END $$;
    """)

    execute("""
    DO $$ BEGIN IF EXISTS (SELECT 1 FROM game_entities WHERE kind='companies' AND (data->>'id') IS DISTINCT FROM id) THEN RAISE EXCEPTION 'Legacy companies ID mismatch'; END IF; END $$;
    """)

    execute("""
    INSERT INTO game_companies (world_id,id,account_id,name,home_port_id,cash_cents,reserved_cents,profit_cents,unpaid_cents,created_ms,last_invite_year) SELECT world_id,id,(data->>'account_id')::text,(data->>'name')::text,(data->>'home')::text,(data->>'cash')::bigint,(data->>'reserved')::bigint,(data->>'profit')::bigint,(data->>'unpaid')::bigint,(data->>'created_ms')::bigint,(data->>'last_invite_year')::bigint FROM game_entities WHERE kind='companies';
    """)

    execute("""
    DO $$ BEGIN IF EXISTS (SELECT 1 FROM game_entities WHERE kind='ships' AND data - ARRAY['id','company_id','name','class','port','status','arrive_ms','destination','depart_ms','fuel_total','fuel_burned','crew_remainder','last_cost_ms','last_liquid','voyage_speedup','cargo']::text[] <> '{}'::jsonb) THEN RAISE EXCEPTION 'Unknown fields in legacy ships; refusing lossy migration'; END IF; END $$;
    """)

    execute("""
    DO $$ BEGIN IF EXISTS (SELECT 1 FROM game_entities WHERE kind='ships' AND (data->>'id') IS DISTINCT FROM id) THEN RAISE EXCEPTION 'Legacy ships ID mismatch'; END IF; END $$;
    """)

    execute("""
    INSERT INTO game_ships (world_id,id,company_id,name,class_id,port_id,status,arrive_ms,destination_port_id,depart_ms,fuel_total_cents,fuel_burned_cents,crew_remainder,last_cost_ms,last_liquid_good_id,voyage_speedup) SELECT world_id,id,(data->>'company_id')::text,(data->>'name')::text,(data->>'class')::text,(data->>'port')::text,(data->>'status')::text,(data->>'arrive_ms')::bigint,(data->>'destination')::text,(data->>'depart_ms')::bigint,(data->>'fuel_total')::bigint,(data->>'fuel_burned')::bigint,(data->>'crew_remainder')::bigint,(data->>'last_cost_ms')::bigint,(data->>'last_liquid')::text,(data->>'voyage_speedup')::bigint FROM game_entities WHERE kind='ships';
    """)

    execute("""
    DO $$ BEGIN IF EXISTS (SELECT 1 FROM game_entities WHERE kind='markets' AND data - ARRAY['port','good','merchant','seller','buyer','stock','demand','budget','last_production','batches']::text[] <> '{}'::jsonb) THEN RAISE EXCEPTION 'Unknown fields in legacy markets; refusing lossy migration'; END IF; END $$;
    """)

    execute("""
    INSERT INTO game_markets (world_id,id,port_id,good_id,merchant,seller,buyer,stock_lots,demand_lots,budget_cents,last_production_ms) SELECT world_id,id,(data->>'port')::text,(data->>'good')::text,(data->>'merchant')::boolean,(data->>'seller')::boolean,(data->>'buyer')::boolean,(data->>'stock')::bigint,(data->>'demand')::bigint,(data->>'budget')::bigint,(data->>'last_production')::bigint FROM game_entities WHERE kind='markets';
    """)

    execute("""
    DO $$ BEGIN IF EXISTS (SELECT 1 FROM game_entities WHERE kind='sessions' AND data - ARRAY['account_id','expires_at']::text[] <> '{}'::jsonb) THEN RAISE EXCEPTION 'Unknown fields in legacy sessions; refusing lossy migration'; END IF; END $$;
    """)

    execute("""
    INSERT INTO game_sessions (world_id,id,account_id,expires_at_ms) SELECT world_id,id,(data->>'account_id')::text,(data->>'expires_at')::bigint FROM game_entities WHERE kind='sessions';
    """)

    execute("""
    DO $$ BEGIN IF EXISTS (SELECT 1 FROM game_entities WHERE kind='invitations' AND data - ARRAY['inviter','expires_ms','status','seed','invitee']::text[] <> '{}'::jsonb) THEN RAISE EXCEPTION 'Unknown fields in legacy invitations; refusing lossy migration'; END IF; END $$;
    """)

    execute("""
    INSERT INTO game_invitations (world_id,id,inviter_account_id,expires_ms,status,seed,invitee_account_id) SELECT world_id,id,(data->>'inviter')::text,(data->>'expires_ms')::bigint,(data->>'status')::text,(data->>'seed')::boolean,(data->>'invitee')::text FROM game_entities WHERE kind='invitations';
    """)

    execute("""
    DO $$ BEGIN IF EXISTS (SELECT 1 FROM game_entities WHERE kind='notices' AND data - ARRAY['account_id','text','clock_ms']::text[] <> '{}'::jsonb) THEN RAISE EXCEPTION 'Unknown fields in legacy notices; refusing lossy migration'; END IF; END $$;
    """)

    execute("""
    INSERT INTO game_notices (world_id,id,account_id,message,clock_ms) SELECT world_id,id,(data->>'account_id')::text,(data->>'text')::text,(data->>'clock_ms')::bigint FROM game_entities WHERE kind='notices';
    """)

    execute("""
    DO $$ BEGIN IF EXISTS (SELECT 1 FROM game_entities e CROSS JOIN LATERAL jsonb_array_elements(e.data->'cargo') b WHERE kind='ships' AND b - ARRAY['quantity','expires_ms','good','unit_cost']::text[] <> '{}'::jsonb) THEN RAISE EXCEPTION 'Unknown batch fields'; END IF; END $$;
    """)

    execute("""
    INSERT INTO game_ship_cargo_batches(world_id,ship_id,position,quantity_lots,expires_ms,good_id,unit_cost_cents) SELECT world_id,id,(ordinality-1)::integer,(b->>'quantity')::bigint,(b->>'expires_ms')::bigint,b->>'good',(b->>'unit_cost')::bigint FROM game_entities e CROSS JOIN LATERAL jsonb_array_elements(e.data->'cargo') WITH ORDINALITY AS batch(b,ordinality) WHERE kind='ships';
    """)

    execute("""
    DO $$ BEGIN IF EXISTS (SELECT 1 FROM game_entities e CROSS JOIN LATERAL jsonb_array_elements(e.data->'batches') b WHERE kind='markets' AND b - ARRAY['quantity','expires_ms']::text[] <> '{}'::jsonb) THEN RAISE EXCEPTION 'Unknown batch fields'; END IF; END $$;
    """)

    execute("""
    INSERT INTO game_market_stock_batches(world_id,market_id,position,quantity_lots,expires_ms) SELECT world_id,id,(ordinality-1)::integer,(b->>'quantity')::bigint,(b->>'expires_ms')::bigint FROM game_entities e CROSS JOIN LATERAL jsonb_array_elements(e.data->'batches') WITH ORDINALITY AS batch(b,ordinality) WHERE kind='markets';
    """)

    execute("""
    SET CONSTRAINTS ALL IMMEDIATE;
    """)

    execute("""
    DROP TABLE game_entities;
    """)
  end

  def down do
    raise "Restore the pre-migration backup to return to legacy storage."
  end
end
