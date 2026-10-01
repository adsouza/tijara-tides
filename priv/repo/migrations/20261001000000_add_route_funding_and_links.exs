defmodule TijaraTides.Infrastructure.Persistence.Repo.Migrations.AddRouteFundingAndLinks do
  use Ecto.Migration

  def up do
    sql = """
    ALTER TABLE game_accounts ADD COLUMN funding_policy text NOT NULL DEFAULT 'wait' CHECK(funding_policy IN ('wait','reduced','skip'));
    ALTER TABLE game_route_stops ADD COLUMN advance_budget bigint CHECK(advance_budget BETWEEN 0 AND 1000000000000);
    ALTER TABLE game_visit_plans ADD COLUMN advance_budget bigint CHECK(advance_budget BETWEEN 0 AND 1000000000000);
    ALTER TABLE game_route_rules ADD COLUMN linked_warehouse_id text;
    ALTER TABLE game_route_rules ADD CHECK(linked_warehouse_id IS NULL OR (side='buy' AND quantity_mode='fixed' AND limit_cents>0));
    ALTER TABLE game_ship_routes ADD COLUMN visit_finished boolean NOT NULL DEFAULT false;
    CREATE TABLE game_remote_links (
      world_id text NOT NULL REFERENCES game_worlds(id) ON DELETE CASCADE,
      id text NOT NULL, company_id text NOT NULL, ship_id text NOT NULL, stop_id text NOT NULL,
      good text NOT NULL REFERENCES game_cargo_types(id), warehouse_id text NOT NULL, port text NOT NULL REFERENCES game_ports(id),
      order_id text NOT NULL, generation bigint NOT NULL CHECK(generation>=0),
      filled bigint NOT NULL CHECK(filled>=0), status text NOT NULL,
      PRIMARY KEY(world_id,id), UNIQUE(world_id,order_id),
      FOREIGN KEY(world_id,company_id) REFERENCES game_companies(world_id,id) ON DELETE CASCADE,
      FOREIGN KEY(world_id,ship_id) REFERENCES game_ships(world_id,id) ON DELETE CASCADE,
      FOREIGN KEY(world_id,id) REFERENCES game_route_rules(world_id,id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
    );
    CREATE TABLE game_visit_budgets (
      world_id text NOT NULL REFERENCES game_worlds(id) ON DELETE CASCADE,
      id text NOT NULL, company_id text NOT NULL, ship_id text NOT NULL, stop_id text,
      port text NOT NULL REFERENCES game_ports(id), amount bigint NOT NULL CHECK(amount BETWEEN 0 AND 1000000000000),
      remaining bigint NOT NULL CHECK(remaining>=0 AND remaining<=amount),
      strict boolean NOT NULL, skip boolean NOT NULL, visit bigint NOT NULL CHECK(visit>=0),
      PRIMARY KEY(world_id,id),
      FOREIGN KEY(world_id,company_id) REFERENCES game_companies(world_id,id) ON DELETE CASCADE,
      FOREIGN KEY(world_id,ship_id) REFERENCES game_ships(world_id,id) ON DELETE CASCADE,
      FOREIGN KEY(world_id,stop_id) REFERENCES game_route_stops(world_id,id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
    );
    CREATE TABLE game_departure_requests (
      world_id text NOT NULL REFERENCES game_worlds(id) ON DELETE CASCADE,
      id text NOT NULL, company_id text NOT NULL, ship_id text NOT NULL, destination text NOT NULL REFERENCES game_ports(id),
      stop_id text, visit bigint NOT NULL CHECK(visit>=0), configured bigint CHECK(configured BETWEEN 0 AND 1000000000000),
      policy text NOT NULL CHECK(policy IN ('wait','reduced','skip')), required bigint NOT NULL CHECK(required>=0),
      blocked_ms bigint NOT NULL CHECK(blocked_ms>=0), accumulated bigint NOT NULL CHECK(accumulated>=0 AND accumulated<=required),
      window_deadline_ms bigint, cooldown_ms bigint, CHECK(id=ship_id),
      CHECK(accumulated=0 OR window_deadline_ms IS NOT NULL),
      PRIMARY KEY(world_id,id),
      FOREIGN KEY(world_id,company_id) REFERENCES game_companies(world_id,id) ON DELETE CASCADE,
      FOREIGN KEY(world_id,ship_id) REFERENCES game_ships(world_id,id) ON DELETE CASCADE
    );
    CREATE UNIQUE INDEX game_one_departure_accumulator ON game_departure_requests(world_id,company_id) WHERE window_deadline_ms IS NOT NULL;
    """

    for statement <- String.split(sql, ";", trim: true), do: execute(statement)
  end

  def down do
    for table <- ~w(game_departure_requests game_visit_budgets game_remote_links),
        do: execute("DROP TABLE " <> table)

    execute("ALTER TABLE game_ship_routes DROP COLUMN visit_finished")
    execute("ALTER TABLE game_route_rules DROP COLUMN linked_warehouse_id")
    execute("ALTER TABLE game_route_stops DROP COLUMN advance_budget")
    execute("ALTER TABLE game_visit_plans DROP COLUMN advance_budget")
    execute("ALTER TABLE game_accounts DROP COLUMN funding_policy")
  end
end
