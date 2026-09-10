defmodule TijaraTidesWeb.FinancialReports do
  use TijaraTidesWeb, :html

  attr :data, :any, default: nil
  attr :open, :boolean, default: false
  attr :error, :any, default: nil

  def panel(assigns) do
    assigns = assign(assigns, :own_page, 0)
    assigns = if assigns.data, do: assign(assigns, assigns.data), else: assigns

    ~H"""
    <div id="financial-reports" class="financial-reports">
      <button
        type="button"
        phx-click={JS.remove_attribute("open", to: "#company-menu") |> JS.push("report-toggle")}
        aria-expanded={to_string(@open)}
        class="popup-menu-trigger"
      >Results &amp; leaderboards</button>
      <div :if={@open && @error} class="financial-reports-body">
        <p>Reports are temporarily unavailable. Please retry.</p>
        <button phx-click="report-refresh">Retry</button>
        <button phx-click="report-toggle">Close</button>
      </div>
      <div :if={@open && @data && !@error} class="financial-reports-body">
        <div class="mb-3 flex items-center justify-between gap-3">
          <h2 class="text-lg font-semibold">Company results &amp; leaderboards</h2>
          <button
            type="button"
            phx-click="report-toggle"
            class="rounded border px-2 py-1"
          >Close</button>
        </div>
        <form
          id="report-selection"
          phx-change="report-selection"
          class="mb-3 flex flex-wrap gap-3 text-sm"
        >
          <label>Period
          <select name="period" class="rounded bg-slate-800 p-2">
            <option value="quarter" selected={@period == "quarter"}>Quarter</option>
            <option value="year" selected={@period == "year"}>Year</option>
          </select></label>
          <label>Ranking
          <select name="metric" class="rounded bg-slate-800 p-2">
            <option value="profit" selected={@metric == "profit"}>Total profit</option>
            <option value="roi" selected={@metric == "roi"}>ROI</option>
          </select></label>
          <label>
            {String.capitalize(@period)}
            <select :if={@period == "quarter"} name="period_number" class="rounded bg-slate-800 p-2">
              <option
                :for={index <- @current..@minimum//-1}
                value={index + 1}
                selected={index == @selected}
              >
                Quarter {index + 1}{if index == @current, do: " (current)", else: ""}
              </option>
            </select>
            <input
              :if={@period == "year"}
              name="period_number"
              type="number"
              min={@minimum + 1}
              max={@current + 1}
              value={@selected + 1}
              class="w-16 rounded bg-slate-800 p-2"
            />
          </label>
          <button type="button" phx-click="report-refresh" class="rounded border px-2">Refresh</button>
        </form>
        <p class="mb-2 text-sm">
          {String.capitalize(@period)} {@selected + 1} · {if @selected == @current,
            do: "In progress",
            else: "Completed"}
        </p>
        <details
          id="about-financial-reports"
          phx-mounted={JS.ignore_attributes("open")}
          class="mb-3 text-xs text-slate-400"
        >
          <summary class="cursor-pointer">About financial reports</summary>
          <p class="mb-3 text-xs text-slate-400">
            One quarter is 7 active-world days; one year is 28. Periods start at world time zero. Rankings require a complete period. ROI uses time-weighted assets, including loan-funded assets. Zero capital is unranked.
          </p>
          <p :if={@own != []} class="mb-3 text-xs text-slate-400">
            Reports include activity recorded since financial tracking began. Earlier activity remains in your lifetime trading result; incomplete periods are not ranked.
          </p>
        </details>
        <section
          :for={row <- @own}
          class="mb-4 rounded border border-slate-700 p-3"
          aria-label="Your company results"
        >
          <h3 class="mb-2 font-semibold">
            {row["name"]} · {if row["eligible"], do: "Final results", else: "Provisional / unranked"}
          </h3>
          <dl class="grid grid-cols-[max-content_minmax(0,1fr)] gap-x-4 gap-y-1 text-sm">
            <dt>Sales revenue</dt><dd class="text-right">{cash(row["revenue"])}</dd>
            <dt>Cargo sold at cost</dt><dd class="text-right">{cash(row["cargo_cost"])}</dd>
            <dt>Operating costs &amp; disposal losses</dt><dd class="text-right">
              {cash(row["operating"])}
            </dd>
            <dt>Depreciation</dt><dd class="text-right">{cash(row["depreciation"])}</dd>
            <dt class="font-semibold">Net profit</dt><dd class="text-right font-semibold">
              {cash(row["profit"])}
            </dd>
            <dt>Average capital employed</dt><dd class="text-right">
              {cash(row["average_capital"])}
            </dd>
            <dt>ROI</dt><dd class="text-right">{roi(row["roi"])}</dd>
          </dl>
        </section>
        <nav
          :if={@own_count > @limit}
          aria-label="Your company history pages"
          class="mb-4 flex items-center justify-between gap-3 text-sm"
        >
          <button
            phx-click="report-own-page"
            phx-value-page={@own_page - 1}
            disabled={@own_page == 0}
            class="rounded border px-2 py-1 disabled:opacity-40"
          >Previous companies</button>
          <span>Your companies · page {@own_page + 1}</span>
          <button
            phx-click="report-own-page"
            phx-value-page={@own_page + 1}
            disabled={(@own_page + 1) * @limit >= @own_count}
            class="rounded border px-2 py-1 disabled:opacity-40"
          >Next companies</button>
        </nav>
        <div class="overflow-x-auto">
          <table class="w-full text-sm" aria-label="Company leaderboard">
            <thead>
              <tr>
                <th class="p-2 text-left">Rank</th><th class="p-2 text-left">Company</th><th class="p-2 text-right">
                  Profit
                </th><th class="p-2 text-right">ROI</th><th class="p-2 text-right">
                  Lifetime bankruptcies
                </th>
              </tr>
            </thead>
            <tbody>
              <tr :for={{row, index} <- Enum.with_index(@ranked, 1)} class="border-t border-slate-700">
                <td class="p-2">{@page * @limit + index}</td><td class="p-2">{row["name"]}</td><td class="p-2 text-right">
                  {cash(row["profit"])}
                </td><td class="p-2 text-right">{roi(row["roi"])}</td><td class="p-2 text-right">
                  {row["bankruptcies"]}
                </td>
              </tr>
            </tbody>
          </table>
          <p :if={@ranked_count == 0} class="my-3 text-sm text-slate-400">
            No eligible companies for this ranking yet.
          </p>
        </div>
        <details
          :if={@provisional != []}
          id="unranked-results"
          phx-mounted={JS.ignore_attributes("open")}
          class="mt-3 text-sm"
        >
          <summary class="cursor-pointer">
            Provisional and unranked companies ({@provisional_count})
          </summary>
          <p :for={row <- @provisional} class="mt-2">
            {row["name"]}: {cash(row["profit"])} profit · {roi(row["roi"])} ROI · {row["bankruptcies"]} lifetime bankruptcies
          </p>
        </details>
        <div class="mt-4 flex items-center justify-between gap-3 text-sm">
          <button
            phx-click="report-page"
            phx-value-page={@page - 1}
            disabled={@page == 0}
            class="rounded border px-2 py-1 disabled:opacity-40"
          >Previous page</button>
          <span>Page {@page + 1} · up to {@limit} companies per list</span>
          <button
            phx-click="report-page"
            phx-value-page={@page + 1}
            disabled={(@page + 1) * @limit >= max(@ranked_count, @provisional_count)}
            class="rounded border px-2 py-1 disabled:opacity-40"
          >Next page</button>
        </div>
      </div>
    </div>
    """
  end

  defp cash(cents),
    do:
      "$" <>
        (Decimal.new(cents) |> Decimal.div(100) |> Decimal.round(0) |> Decimal.to_string(:normal))

  defp roi(nil), do: "—"
  defp roi(value), do: :erlang.float_to_binary(value * 1.0, decimals: 2) <> "%"
end
