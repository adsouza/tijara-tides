defmodule TijaraTides.Infrastructure.Persistence.Repo.Migrations.AddShipInstructions do
  use Ecto.Migration

  def change do
    execute(
      """
      CREATE TABLE game_ship_instructions (
        world_id text NOT NULL REFERENCES game_worlds(id) ON DELETE CASCADE,
        id text NOT NULL,
        company_id text NOT NULL,
        ship_id text NOT NULL,
        port_id text NOT NULL REFERENCES game_ports(id),
        good_id text NOT NULL REFERENCES game_cargo_types(id),
        side text NOT NULL CHECK (side IN ('buy','sell')),
        quantity_lots bigint NOT NULL CHECK (quantity_lots BETWEEN 1 AND 10000),
        filled_lots bigint NOT NULL CHECK (filled_lots BETWEEN 0 AND quantity_lots),
        limit_cents bigint NOT NULL CHECK (limit_cents >= 0),
        budget_cents bigint,
        spent_cents bigint NOT NULL CHECK (spent_cents >= 0),
        onward_port_id text REFERENCES game_ports(id),
        status text NOT NULL CHECK (status IN ('planned','waiting','filled','cancelled')),
        reason text NOT NULL,
        created_ms bigint NOT NULL,
        PRIMARY KEY(world_id,id),
        FOREIGN KEY(world_id,company_id) REFERENCES game_companies(world_id,id) ON DELETE CASCADE,
        FOREIGN KEY(world_id,ship_id) REFERENCES game_ships(world_id,id) ON DELETE CASCADE,
        CHECK (side <> 'buy' OR (budget_cents > 0 AND spent_cents <= budget_cents AND onward_port_id IS NOT NULL AND onward_port_id <> port_id))
      )
      """,
      "DROP TABLE game_ship_instructions"
    )

    create(index(:game_ship_instructions, [:world_id, :ship_id]))

    execute(
      """
      CREATE TABLE game_visit_plans (
        world_id text NOT NULL REFERENCES game_worlds(id) ON DELETE CASCADE,
        id text NOT NULL,
        ship_id text NOT NULL,
        company_id text NOT NULL,
        port_id text NOT NULL REFERENCES game_ports(id),
        onward_port_id text NOT NULL REFERENCES game_ports(id),
        auto_depart boolean NOT NULL DEFAULT false,
        departure_wait text,
        PRIMARY KEY(world_id,id),
        UNIQUE(world_id,ship_id,port_id),
        FOREIGN KEY(world_id,ship_id) REFERENCES game_ships(world_id,id) ON DELETE CASCADE,
        FOREIGN KEY(world_id,company_id) REFERENCES game_companies(world_id,id) ON DELETE CASCADE,
        CHECK(port_id <> onward_port_id)
      )
      """,
      "DROP TABLE game_visit_plans"
    )
  end
end
