defmodule TijaraTides.Infrastructure.Persistence.Repo.Migrations.AddRepeatingRoutes do
  use Ecto.Migration

  def change do
    execute(
      """
      CREATE TABLE game_ship_routes (
        world_id text NOT NULL REFERENCES game_worlds(id) ON DELETE CASCADE,
        id text NOT NULL, ship_id text NOT NULL, company_id text NOT NULL,
        status text NOT NULL CHECK(status IN ('draft','running','paused')),
        cursor integer NOT NULL CHECK(cursor BETWEEN 0 AND 7),
        visit bigint NOT NULL CHECK(visit >= 0),
        phase text NOT NULL CHECK(phase IN ('arrival','selling','buying')),
        auto_depart boolean NOT NULL DEFAULT false, stop_after boolean NOT NULL DEFAULT false,
        reason text NOT NULL,
        PRIMARY KEY(world_id,id), UNIQUE(world_id,ship_id,company_id), CHECK(id=ship_id),
        FOREIGN KEY(world_id,ship_id) REFERENCES game_ships(world_id,id) ON DELETE CASCADE,
        FOREIGN KEY(world_id,company_id) REFERENCES game_companies(world_id,id) ON DELETE CASCADE
      )
      """,
      "DROP TABLE game_ship_routes"
    )

    execute(
      """
      CREATE TABLE game_route_stops (
        world_id text NOT NULL, id text NOT NULL, ship_id text NOT NULL, company_id text NOT NULL,
        position integer NOT NULL CHECK(position BETWEEN 0 AND 7),
        port_id text NOT NULL REFERENCES game_ports(id),
        PRIMARY KEY(world_id,id), UNIQUE(world_id,id,ship_id,company_id),
        UNIQUE(world_id,ship_id,position) DEFERRABLE INITIALLY DEFERRED,
        FOREIGN KEY(world_id,ship_id,company_id) REFERENCES game_ship_routes(world_id,ship_id,company_id) ON DELETE CASCADE
      )
      """,
      "DROP TABLE game_route_stops"
    )

    execute(
      """
      CREATE TABLE game_route_rules (
        world_id text NOT NULL, id text NOT NULL, ship_id text NOT NULL, company_id text NOT NULL, stop_id text NOT NULL,
        good_id text NOT NULL REFERENCES game_cargo_types(id),
        side text NOT NULL CHECK(side IN ('buy','sell')),
        quantity_lots bigint NOT NULL CHECK(quantity_lots BETWEEN 1 AND 10000),
        limit_cents bigint NOT NULL CHECK(limit_cents BETWEEN 0 AND 1000000000000),
        budget_cents bigint,
        PRIMARY KEY(world_id,id), UNIQUE(world_id,stop_id,side,good_id),
        FOREIGN KEY(world_id,stop_id,ship_id,company_id) REFERENCES game_route_stops(world_id,id,ship_id,company_id) ON DELETE CASCADE,
        CHECK(side <> 'buy' OR (budget_cents IS NOT NULL AND budget_cents BETWEEN 1 AND 1000000000000))
      )
      """,
      "DROP TABLE game_route_rules"
    )
  end
end
