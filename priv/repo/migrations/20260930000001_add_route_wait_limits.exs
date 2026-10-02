defmodule TijaraTides.Infrastructure.Persistence.Repo.Migrations.AddRouteWaitLimits do
  use Ecto.Migration

  def change do
    alter table(:game_route_stops) do
      add(:max_wait_ms, :bigint)
    end

    create(
      constraint(:game_route_stops, :route_max_wait_range,
        check: "max_wait_ms IS NULL OR max_wait_ms BETWEEN 1 AND 2592000000"
      )
    )

    alter table(:game_ship_routes) do
      add(:visit_arrived_ms, :bigint)
      add(:wait_deadline_ms, :bigint)
      add(:wait_timed_out, :boolean, null: false, default: false)
    end

    create(
      constraint(:game_ship_routes, :route_arrival_range,
        check: "visit_arrived_ms IS NULL OR visit_arrived_ms >= 0"
      )
    )

    create(
      constraint(:game_ship_routes, :route_wait_deadline,
        check:
          "wait_deadline_ms IS NULL OR (visit_arrived_ms IS NOT NULL AND wait_deadline_ms > visit_arrived_ms)"
      )
    )
  end
end
