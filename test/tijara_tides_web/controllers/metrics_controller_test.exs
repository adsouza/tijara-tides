defmodule TijaraTidesWeb.MetricsControllerTest do
  use TijaraTidesWeb.ConnCase, async: false

  test "scrapes cumulative metrics without sessions, SQL labels or a world call", %{conn: conn} do
    native = System.convert_time_unit(25, :millisecond, :native)

    :telemetry.execute(
      [:tijara_tides, :infrastructure, :persistence, :repo, :query],
      %{query_time: native, queue_time: 0, decode_time: 0, total_time: native},
      %{query: "secret-sql", params: ["secret-token"]}
    )

    :telemetry.execute([:tijara_tides, :owner], %{mailbox_depth: 7}, %{})
    :telemetry.execute([:tijara_tides, :tick], %{lag: 250}, %{})
    :telemetry.execute([:tijara_tides, :conflict], %{count: 1}, %{outcome: :retry})

    conn = get(conn, ~p"/metrics")
    body = response(conn, 200)
    assert body =~ "# TYPE tijara_database_query_time_seconds histogram"
    assert body =~ "tijara_database_query_time_seconds_count"
    assert body =~ "tijara_owner_mailbox_depth 7"
    assert body =~ "tijara_tick_lag_seconds"
    assert body =~ ~s(tijara_conflicts_total{outcome="retry"})
    refute body =~ "secret-sql"
    refute body =~ "secret-token"
    assert get_resp_header(conn, "set-cookie") == []
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]

    # Internal aggregation does not reset the counters exposed to Prometheus.
    :ok = TijaraTidesWeb.Telemetry.aggregate()
    assert TijaraTidesWeb.Telemetry.scrape() =~ "tijara_database_query_time_seconds_count"
  end
end
