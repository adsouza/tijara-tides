defmodule TijaraTides.Domain.CompanyFinance.Guarantees do
  @moduledoc "Cash-backed sponsor guarantees, held separately from spendable company cash."
  import TijaraTides.Domain.State
  alias TijaraTides.Domain.Notices
  alias TijaraTides.Domain.CompanyFinance, as: Finance

  defdelegate suspended?(account), to: TijaraTides.Domain.Account

  def sponsor_eligible?(state, sponsor) do
    company = get(state, "companies", sponsor["company_id"])

    debt =
      Enum.sum(
        for loan <- Finance.loans(state, sponsor["company_id"]),
            do: loan["remaining"] + loan["interest_due"] + loan["interest_accrued"]
      )

    not suspended?(sponsor) and company != nil and company["bankruptcy_ms"] == nil and
      company["unpaid"] == 0 and debt <= company["cash"] - company["reserved"] and
      Enum.all?(
        Finance.loans(state, sponsor["company_id"]),
        &(&1["principal_due"] == 0 and &1["interest_due"] == 0)
      )
  end

  def active(state, account_id) do
    Enum.find_value(entities(state, "guarantees"), fn {_, g} ->
      if g["beneficiary_id"] == account_id and g["status"] == "pledged", do: g
    end)
  end

  def pledge(state, sponsor, beneficiary_id, amount, id) do
    state = Finance.settle(state, [sponsor["company_id"]])
    sponsor = get(state, "accounts", sponsor["id"])
    beneficiary = get(state, "accounts", beneficiary_id)
    company = get(state, "companies", sponsor["company_id"])

    cond do
      is_nil(beneficiary) or beneficiary["inviter"] != sponsor["id"] or
          beneficiary_id == sponsor["id"] ->
        {:error, :guarantee_not_sponsor}

      not sponsor_eligible?(state, sponsor) ->
        {:error, :guarantee_sponsor_unavailable}

      not suspended?(beneficiary) and Finance.rate(state, beneficiary) < 1600 ->
        {:error, :guarantee_not_required}

      active(state, beneficiary_id) != nil ->
        {:error, :guarantee_exists}

      not is_integer(amount) or amount < 5_000_000 or
          amount > Finance.credit_limit(state, beneficiary) ->
        {:error, :guarantee_amount}

      amount > company["cash"] - company["reserved"] ->
        {:error, :guarantee_funds}

      true ->
        g = %{
          "id" => id,
          "company_id" => company["id"],
          "sponsor_id" => sponsor["id"],
          "beneficiary_id" => beneficiary_id,
          "borrower_company_id" => nil,
          "amount" => amount,
          "forfeited" => 0,
          "status" => "pledged",
          "created_ms" => state.clock_ms
        }

        state =
          state
          |> put("guarantees", id, g)
          |> TijaraTides.Domain.Account.reinstate(beneficiary_id, id)
          |> Finance.post(company["id"], "guarantee_pledge", [
            {"guarantee_escrow", amount},
            {"cash_available", -amount}
          ])
          |> Notices.notice(
            beneficiary_id,
            "guarantee:" <> id,
            "Your sponsor has funded a guarantee. Your account is reinstated; the bankruptcy restart cooldown still applies."
          )

        {:ok, state, %{"guarantee_id" => id, "pledged" => amount}}
    end
  end

  def drawn(state, account) do
    case active(state, account["id"]) do
      nil ->
        state

      g ->
        put(state, "guarantees", g["id"], %{g | "borrower_company_id" => account["company_id"]})
    end
  end

  def settle(state, company_ids \\ :all) do
    guarantees =
      if company_ids == :all,
        do: Map.values(entities(state, "guarantees")),
        else:
          Enum.flat_map(
            Enum.uniq(company_ids) -- [nil],
            &owned(state, "guarantees", "borrower_company_id", &1)
          )

    Enum.reduce(guarantees, state, fn g, acc ->
      if g["status"] == "pledged" and g["borrower_company_id"] != nil and
           Enum.all?(Finance.loans(acc, g["borrower_company_id"]), &(&1["status"] == "repaid")) do
        close(acc, g, 0)
      else
        acc
      end
    end)
  end

  def default(state, account, debt) do
    case active(state, account["id"]) do
      nil -> state
      g -> close(state, g, min(g["amount"], debt))
    end
  end

  defp close(state, g, loss) do
    company = get(state, "companies", g["company_id"])
    refund = g["amount"] - loss

    state
    |> put("guarantees", g["id"], %{
      g
      | "status" => if(loss > 0, do: "claimed", else: "released"),
        "forfeited" => loss
    })
    |> Finance.post(company["id"], "guarantee_settlement", [
      {"cash_available", refund},
      {"guarantee_expense", loss},
      {"guarantee_escrow", -g["amount"]}
    ])
    |> Notices.notice(
      g["sponsor_id"],
      "guarantee:" <> g["id"],
      "Your guarantee has settled: $#{div(loss, 100)} forfeited and $#{div(refund, 100)} returned to the sponsoring company."
    )
  end

  defp invitee_name(state, account) do
    company =
      entities(state, "companies")
      |> Map.values()
      |> Enum.filter(&(&1["account_id"] == account["id"]))
      |> Enum.max_by(&{&1["created_ms"], &1["id"]}, fn -> nil end)

    if company, do: company["name"], else: "Invitee " <> String.slice(account["id"], 0, 8)
  end

  def view(state, account) do
    pending =
      entities(state, "accounts")
      |> Map.values()
      |> Enum.filter(
        &(&1["inviter"] == account["id"] and (suspended?(&1) or Finance.rate(state, &1) == 1600) and
            active(state, &1["id"]) == nil)
      )
      |> Enum.sort_by(& &1["id"])
      |> Enum.map(fn a ->
        %{
          "id" => a["id"],
          "name" => invitee_name(state, a),
          "limit" => Finance.credit_limit(state, a)
        }
      end)

    %{
      "pending" => pending,
      "eligible" => sponsor_eligible?(state, account),
      "has_sponsor" => account["inviter"] != nil,
      "active" => active(state, account["id"]),
      "pledges" =>
        entities(state, "guarantees")
        |> Map.values()
        |> Enum.filter(&(&1["sponsor_id"] == account["id"]))
    }
  end
end
