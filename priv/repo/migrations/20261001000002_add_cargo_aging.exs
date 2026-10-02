defmodule TijaraTides.Repo.Migrations.AddCargoAging do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE game_cargo_holdings ADD COLUMN freshness jsonb CHECK(freshness IS NULL OR jsonb_typeof(freshness)='object')"
    )

    execute(
      "ALTER TABLE game_warehouses ADD COLUMN aging_bps bigint NOT NULL DEFAULT 2500 CHECK(aging_bps BETWEEN 1 AND 10000)"
    )

    execute(
      "ALTER TABLE game_merchant_warehouses ADD COLUMN aging_bps bigint NOT NULL DEFAULT 2500 CHECK(aging_bps BETWEEN 1 AND 10000)"
    )

    # Retain legacy biological age and original tuning. Cooling begins at migration.
    execute("""
    UPDATE game_cargo_holdings h SET freshness=jsonb_build_object(
      'origin_expires_ms',l.expires_ms,'expires_ms',l.expires_ms,
      'harvest_ms',l.expires_ms-CASE l.good_id WHEN 'fruit' THEN 25920000 WHEN 'meat' THEN 17280000 ELSE 12960000 END,
      'shelf_ms',CASE l.good_id WHEN 'fruit' THEN 25920000 WHEN 'meat' THEN 17280000 ELSE 12960000 END,
      'at_ms',w.clock_ms,'remaining_units',greatest(0,l.expires_ms-w.clock_ms)*10000,'rate_bps',10000)
    FROM game_cargo_lots l,game_worlds w WHERE l.world_id=h.world_id AND l.id=h.lot_id AND w.id=h.world_id AND l.expires_ms IS NOT NULL
    """)

    execute("""
    UPDATE game_cargo_holdings h SET freshness=h.freshness || jsonb_build_object(
      'rate_bps',2500,'expires_ms',w.clock_ms+greatest(0,(h.freshness->>'origin_expires_ms')::bigint-w.clock_ms)*4)
    FROM game_worlds w WHERE w.id=h.world_id AND h.freshness IS NOT NULL AND (
      EXISTS(SELECT 1 FROM game_ships s WHERE s.world_id=h.world_id AND s.id=h.ship_id AND s.class_id='reefer') OR
      EXISTS(SELECT 1 FROM game_warehouses s WHERE s.world_id=h.world_id AND s.id=h.warehouse_id AND s.storage='reefer') OR
      EXISTS(SELECT 1 FROM game_merchant_warehouses s WHERE s.world_id=h.world_id AND s.id=h.market_id AND s.storage='reefer'))
    """)

    execute("""
    UPDATE game_warehouse_liquidations p SET clearance_remainders=coalesce((
      SELECT jsonb_object_agg(key, jsonb_build_object('numerator',value::bigint,'denominator',10000::bigint*CASE key WHEN 'fruit' THEN 25920000 WHEN 'meat' THEN 17280000 WHEN 'seafood' THEN 12960000 ELSE 1 END))
      FROM jsonb_each_text(p.clearance_remainders)), '{}'::jsonb) WHERE status<>'completed'
    """)

    execute("""
    CREATE OR REPLACE VIEW game_ship_cargo_batches AS
      SELECT h.world_id,h.ship_id,h.position,h.quantity_lots,coalesce((h.freshness->>'expires_ms')::bigint,l.expires_ms) AS expires_ms,l.good_id,h.unit_cost_cents,h.lot_id,h.freshness
      FROM game_cargo_holdings h JOIN game_cargo_lots l ON l.world_id=h.world_id AND l.id=h.lot_id WHERE h.ship_id IS NOT NULL
    """)

    execute("""
    CREATE OR REPLACE VIEW game_warehouse_cargo_batches AS
      SELECT h.world_id,h.warehouse_id,h.position,h.quantity_lots,coalesce((h.freshness->>'expires_ms')::bigint,l.expires_ms) AS expires_ms,l.good_id,h.unit_cost_cents,h.lot_id,h.freshness
      FROM game_cargo_holdings h JOIN game_cargo_lots l ON l.world_id=h.world_id AND l.id=h.lot_id WHERE h.warehouse_id IS NOT NULL
    """)

    execute("""
    CREATE OR REPLACE VIEW game_market_stock_batches AS
      SELECT h.world_id,h.market_id,h.position,h.quantity_lots,coalesce((h.freshness->>'expires_ms')::bigint,l.expires_ms) AS expires_ms,h.lot_id,h.freshness
      FROM game_cargo_holdings h JOIN game_cargo_lots l ON l.world_id=h.world_id AND l.id=h.lot_id WHERE h.market_id IS NOT NULL
    """)

    execute("""
    CREATE FUNCTION validate_cargo_age() RETURNS trigger LANGUAGE plpgsql AS $$
    DECLARE f jsonb; previous jsonb; origin bigint; remaining bigint; rate bigint; at_ms bigint;
    BEGIN
      f:=NEW.freshness;
      IF f IS NULL THEN
        IF TG_OP='UPDATE' AND OLD.freshness IS NOT NULL THEN RAISE EXCEPTION 'Cargo age cannot be removed'; END IF;
        RETURN NEW;
      END IF;
      IF NOT (f ?& ARRAY['origin_expires_ms','expires_ms','harvest_ms','shelf_ms','at_ms','remaining_units','rate_bps']) OR
        EXISTS(SELECT 1 FROM jsonb_each(f) WHERE jsonb_typeof(value)<>'number') THEN RAISE EXCEPTION 'Invalid cargo age fields'; END IF;
      SELECT expires_ms INTO STRICT origin FROM game_cargo_lots WHERE world_id=NEW.world_id AND id=NEW.lot_id;
      remaining:=(f->>'remaining_units')::bigint; rate:=(f->>'rate_bps')::bigint; at_ms:=(f->>'at_ms')::bigint;
      IF origin IS NULL OR (f->>'origin_expires_ms')::bigint IS DISTINCT FROM origin OR
        (f->>'shelf_ms')::bigint<=0 OR origin<>(f->>'harvest_ms')::bigint+(f->>'shelf_ms')::bigint OR
        remaining<0 OR rate NOT BETWEEN 1 AND 10000 OR at_ms<0 OR
        (remaining>0 AND (f->>'expires_ms')::bigint<>at_ms+(remaining+rate-1)/rate) OR
        (remaining=0 AND (f->>'expires_ms')::bigint>at_ms) THEN RAISE EXCEPTION 'Invalid cargo age'; END IF;
      IF TG_OP='UPDATE' AND OLD.freshness IS NOT NULL THEN
        previous:=OLD.freshness;
        IF f->'harvest_ms' IS DISTINCT FROM previous->'harvest_ms' OR f->'shelf_ms' IS DISTINCT FROM previous->'shelf_ms' OR
          at_ms<(previous->>'at_ms')::bigint OR remaining<>greatest(0,(previous->>'remaining_units')::bigint-(at_ms-(previous->>'at_ms')::bigint)*(previous->>'rate_bps')::bigint)
          THEN RAISE EXCEPTION 'Cargo transfer must preserve biological age'; END IF;
      END IF;
      RETURN NEW;
    END $$
    """)

    execute(
      "CREATE TRIGGER validate_cargo_age BEFORE INSERT OR UPDATE ON game_cargo_holdings FOR EACH ROW EXECUTE FUNCTION validate_cargo_age()"
    )
  end

  def down, do: raise("Cargo biological age must survive reload")
end
