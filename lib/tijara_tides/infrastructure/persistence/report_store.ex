defmodule TijaraTides.Infrastructure.Persistence.ReportStore do
  @moduledoc "PostgreSQL report pages. History never enters the authoritative world snapshot."
  @behaviour TijaraTides.UseCases.ReportStore
  alias TijaraTides.UseCases.ReportQueries

  @impl true
  def page(%{repo: repo, world_id: world}, selection, owner, expected) do
    repo.transaction(fn ->
      repo.query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY", [])

      case repo.query!("SELECT epoch,revision,clock_ms FROM game_worlds WHERE id=$1", [world]).rows do
        [[epoch, revision, clock]]
        when epoch == expected.epoch and revision == expected.revision and
               clock == expected.clock_ms ->
          :ok

        _ ->
          repo.rollback(:report_revision_changed)
      end

      start = selection.selected * selection.duration
      finish = start + selection.duration

      params = [
        world,
        selection.period,
        selection.selected,
        expected.clock_ms,
        start,
        finish,
        selection.duration
      ]

      # The persisted current accumulator may lag behind an unrelated company's command.
      # Add only the unobserved tail; this read never changes or saves it.
      base = """
      WITH raw AS (
        SELECT c.id AS company_id, c.name, c.account_id, c.bankruptcy_ms, a.bankruptcies,
          coalesce(r.id,c.id || ':' || $2 || ':' || $3::bigint::text) AS id,
          $2::text AS period,$3::bigint AS period_index,
          coalesce(r.revenue,0) AS revenue,coalesce(r.cargo_cost,0) AS cargo_cost,
          coalesce(r.operating,0) AS operating,coalesce(r.depreciation,0) AS depreciation,
          coalesce(r.observed_ms,0)+greatest(0,least($4::bigint,$6::bigint)-greatest(t.at_ms,$5::bigint)) AS observed_ms,
          coalesce(r.capital_ms,0)+t.capital::numeric*greatest(0,least($4::bigint,$6::bigint)-greatest(t.at_ms,$5::bigint)) AS capital_ms
        FROM game_reporting_accounts t
        JOIN game_companies c ON c.world_id=t.world_id AND c.id=t.id
        JOIN game_accounts a ON a.world_id=c.world_id AND a.id=c.account_id
        LEFT JOIN game_financial_reports r ON r.world_id=c.world_id AND r.company_id=c.id AND r.period=$2 AND r.period_index=$3::bigint
        WHERE t.world_id=$1 AND t.since_ms<$6::bigint AND c.created_ms<$6::bigint
      ), measured AS (
        SELECT *, revenue-cargo_cost-operating-depreciation AS profit,
          ($6::bigint <= $4::bigint AND capital_ms>0 AND observed_ms=$7::bigint AND (bankruptcy_ms IS NULL OR bankruptcy_ms >= $6::bigint)) AS eligible
        FROM raw
      ), reports AS (
        SELECT *, CASE WHEN capital_ms>0 THEN profit::numeric*observed_ms/capital_ms*100 END AS roi FROM measured
      )
      """

      order = if selection.metric == "roi", do: "roi", else: "profit"

      ranked =
        fetch(
          repo,
          base,
          params,
          "eligible",
          "#{order} DESC, name, company_id",
          selection,
          expected.clock_ms
        )

      provisional =
        fetch(
          repo,
          base,
          params,
          "NOT eligible",
          "name, company_id",
          selection,
          expected.clock_ms
        )

      # Owner history has an independent cursor so leaderboard navigation preserves it.
      own =
        if owner,
          do:
            fetch(
              repo,
              base,
              params ++ [owner],
              "account_id=$8",
              "name, company_id",
              %{selection | page: selection.own_page},
              expected.clock_ms
            ),
          else: {[], 0}

      %{
        ranked: elem(ranked, 0),
        ranked_count: elem(ranked, 1),
        provisional: elem(provisional, 0),
        provisional_count: elem(provisional, 1),
        own: elem(own, 0),
        own_count: elem(own, 1)
      }
    end)
  end

  defp fetch(repo, base, params, where, order, selection, clock) do
    [[count]] = repo.query!(base <> "SELECT count(*) FROM reports WHERE " <> where, params).rows
    n = length(params)

    result =
      repo.query!(
        base <>
          "SELECT * FROM reports WHERE #{where} ORDER BY #{order} LIMIT $#{n + 1} OFFSET $#{n + 2}",
        params ++ [selection.limit, selection.page * selection.limit]
      )

    rows =
      Enum.map(result.rows, fn values ->
        Enum.zip(result.columns, values)
        |> Map.new(fn
          {"capital_ms", value} -> {"capital_ms", Decimal.to_integer(value)}
          {key, value} -> {key, value}
        end)
        |> ReportQueries.decorate(clock)
      end)

    {rows, count}
  end
end
