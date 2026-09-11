defmodule TijaraTides.UseCases.ReportQueries do
  @moduledoc "Reporting selection, eligibility, privacy and presentation-neutral read models."
  alias TijaraTides.Domain.{Account, Reporting}

  @public ~w(id company_id name bankruptcies period period_index profit roi eligible complete end_ms)
  @limit 10

  def selection(clock, params) do
    period = if params["period"] == "year", do: "year", else: "quarter"
    metric = if params["metric"] == "roi", do: "roi", else: "profit"
    current = div(clock, Reporting.duration(period))
    minimum = if period == "quarter", do: max(0, current - 3), else: 0
    index = integer(params["index"], max(0, current - 1)) |> max(minimum) |> min(current)
    page = integer(params["page"], 0) |> max(0) |> min(100_000)

    %{
      period: period,
      metric: metric,
      selected: index,
      current: current,
      minimum: minimum,
      page: page,
      own_page: integer(params["own_page"], 0) |> max(0) |> min(100_000),
      limit: @limit,
      duration: Reporting.duration(period)
    }
  end

  defp integer(n, _) when is_integer(n), do: n

  defp integer(value, default) do
    case Integer.parse(to_string(value || "")) do
      {n, ""} -> n
      _ -> default
    end
  end

  # Planning is pure and cheap, so the world owner can do it; fetching is a bounded read
  # of one committed revision and belongs in whichever process asked for the page.
  def plan(game, session, wall_ms, params) do
    owner =
      case Account.authenticate(game, session, wall_ms) do
        {:ok, account} -> account["id"]
        _ -> nil
      end

    %{
      selection: selection(game.clock_ms, params),
      owner: owner,
      expected: Map.take(game, [:epoch, :revision, :clock_ms])
    }
  end

  def fetch(plan, {store, context}) do
    with {:ok, page} <- store.page(context, plan.selection, plan.owner, plan.expected) do
      {:ok,
       Map.merge(plan.selection, %{
         ranked: Enum.map(page.ranked, &public_row/1),
         provisional: Enum.map(page.provisional, &public_row/1),
         own: page.own,
         ranked_count: page.ranked_count,
         provisional_count: page.provisional_count,
         own_count: page.own_count,
         clock_ms: plan.expected.clock_ms
       })}
    end
  end

  def run(game, session, wall_ms, params, store),
    do: game |> plan(session, wall_ms, params) |> fetch(store)

  def public_row(row), do: Map.take(row, @public)

  # The adapter supplies authoritative selected-period rows, already scoped by owner before loading.
  def decorate(row, clock) do
    finish = (row["period_index"] + 1) * Reporting.duration(row["period"])
    profit = row["revenue"] - row["cargo_cost"] - row["operating"] - row["depreciation"]

    eligible =
      finish <= clock and row["capital_ms"] > 0 and
        row["observed_ms"] == Reporting.duration(row["period"]) and
        (is_nil(row["bankruptcy_ms"]) or row["bankruptcy_ms"] >= finish)

    Map.merge(row, %{
      "profit" => profit,
      "average_capital" =>
        if(row["observed_ms"] > 0, do: div(row["capital_ms"], row["observed_ms"]), else: 0),
      "eligible" => eligible,
      "complete" => finish <= clock,
      "end_ms" => finish,
      "roi" =>
        if(row["capital_ms"] > 0, do: profit * row["observed_ms"] / row["capital_ms"] * 100)
    })
  end
end
