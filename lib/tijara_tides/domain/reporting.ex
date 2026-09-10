defmodule TijaraTides.Domain.Reporting do
  @moduledoc "Fixed active-world periods, journal-derived results and integer capital-time integrals."
  import TijaraTides.Domain.State
  @quarter 7 * 86_400_000
  @assets ~w(cash_available cash_reserved inventory fleet guarantee_escrow)
  @expenses ~w(cost_of_goods handling_expense cleaning_expense fuel_expense crew_expense spoilage_expense canal_expense interest_expense depreciation_expense ship_disposal_expense guarantee_expense)
  @fields ~w(revenue cargo_cost operating depreciation)

  def duration("quarter"), do: @quarter
  def duration("year"), do: @quarter * 4

  def initialize(state, adjustments \\ %{}) do
    Enum.reduce(entities(state, "companies"), state, fn {id, _}, state ->
      ensure(state, id, Map.get(adjustments, id, 0))
    end)
  end

  defp ensure(state, id, delta) do
    if get(state, "reporting_accounts", id) do
      state
    else
      ships = entities(state, "ships") |> Map.values() |> Enum.filter(&(&1["company_id"] == id))
      company = get(state, "companies", id)

      capital =
        company["cash"] +
          Enum.sum(
            for s <- ships,
                do:
                  s["book_value"] +
                    Enum.sum(for c <- s["cargo"], do: c["quantity"] * c["unit_cost"])
          ) +
          Enum.sum(
            for {_, g} <- entities(state, "guarantees"),
                g["company_id"] == id and g["status"] == "pledged",
                do: g["amount"]
          )

      put(state, "reporting_accounts", id, %{
        "id" => id,
        "capital" => capital - delta,
        "since_ms" => state.clock_ms,
        "at_ms" => state.clock_ms
      })
    end
  end

  # Readers reconstruct the tail an account has not observed yet from its at_ms, so an
  # idle company only has to be accrued when a period closes. A year is four quarters,
  # so a quarter boundary is the only boundary either period can cross.
  def advance(state) do
    state = initialize(state)

    Enum.reduce(entities(state, "reporting_accounts"), state, fn {id, account}, state ->
      if div(account["at_ms"], @quarter) == div(state.clock_ms, @quarter),
        do: state,
        else: accrue(state, id)
    end)
  end

  def asset_delta(entries),
    do: Enum.sum(for {code, amount} <- entries, code in @assets, do: amount)

  def post(state, id, entries) do
    delta = asset_delta(entries)
    state = state |> ensure(id, delta) |> accrue(id)

    state =
      Enum.reduce(["quarter", "year"], state, fn period, state ->
        row = row(state, id, period, div(state.clock_ms, duration(period)))

        row =
          Enum.reduce(entries, row, fn {code, amount}, row ->
            case category(code) do
              nil ->
                row

              field ->
                Map.update!(row, field, &(&1 + if(field == "revenue", do: -amount, else: amount)))
            end
          end)

        put(state, "financial_reports", row["id"], row)
      end)

    account = get(state, "reporting_accounts", id)
    put(state, "reporting_accounts", id, Map.update!(account, "capital", &(&1 + delta)))
  end

  defp category("sales_revenue"), do: "revenue"
  defp category("cost_of_goods"), do: "cargo_cost"
  defp category("depreciation_expense"), do: "depreciation"
  defp category(code) when code in @expenses, do: "operating"
  defp category(_), do: nil

  defp row(state, company, period, index) do
    id = "#{company}:#{period}:#{index}"

    get(state, "financial_reports", id) ||
      Map.merge(Map.new(@fields, &{&1, 0}), %{
        "id" => id,
        "company_id" => company,
        "period" => period,
        "period_index" => index,
        "capital_ms" => 0,
        "observed_ms" => 0
      })
  end

  defp accrue(state, id) do
    account = get(state, "reporting_accounts", id)

    state =
      Enum.reduce(["quarter", "year"], state, fn period, state ->
        integrate(state, id, period, account["at_ms"], state.clock_ms, account["capital"])
      end)

    put(state, "reporting_accounts", id, Map.put(account, "at_ms", state.clock_ms))
  end

  defp integrate(state, _, _, from, until, _) when from >= until, do: state

  defp integrate(state, company, period, from, until, capital) do
    index = div(from, duration(period))
    finish = min(until, (index + 1) * duration(period))
    row = row(state, company, period, index)

    row =
      row
      |> Map.update!("capital_ms", &(&1 + capital * (finish - from)))
      |> Map.update!("observed_ms", &(&1 + finish - from))

    state = put(state, "financial_reports", row["id"], row)
    integrate(state, company, period, finish, until, capital)
  end

  def compact(state) do
    rows =
      entities(state, "financial_reports")
      |> Map.filter(fn {_, row} ->
        row["period_index"] == div(state.clock_ms, duration(row["period"]))
      end)

    %{state | entities: Map.put(state.entities, "financial_reports", rows)}
  end
end
