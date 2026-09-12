defmodule TijaraTides.Domain.CompanyFinance.Guarantees do
  @moduledoc "Cash-backed sponsor guarantees, held separately from spendable company cash."
  import TijaraTides.Domain.State
  alias TijaraTides.Domain.Notices
  alias TijaraTides.Domain.CompanyFinance, as: Finance

  @minimum_pledge 5_000_000
  def minimum_pledge, do: @minimum_pledge

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

      not is_integer(amount) or amount < @minimum_pledge or
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

  @doc """
  Settle escrow held by these sponsoring companies. The guarantee row is the sponsor's,
  so only the sponsor's own transaction closes it; borrower state is read, never written.
  """
  def settle(state, company_ids \\ :all) do
    guarantees =
      if company_ids == :all,
        do: Map.values(entities(state, "guarantees")),
        else:
          Enum.flat_map(
            Enum.uniq(company_ids) -- [nil],
            &owned(state, "guarantees", "company_id", &1)
          )

    Enum.reduce(guarantees, state, fn g, acc ->
      case outcome(acc, g) do
        nil -> acc
        {_reason, loss} -> close(acc, g, loss)
      end
    end)
  end

  @doc "The settlement a pledged guarantee is already owed, before its sponsor has settled it."
  def outcome(state, %{"status" => "pledged"} = g) do
    case failure(state, g) do
      %{"guaranteed_debt" => debt} ->
        {"claim", min(g["amount"], debt || 0)}

      nil ->
        loans = owned(state, "loans", "guarantee_id", g["id"])
        repaid? = loans != [] and Enum.all?(loans, &(&1["status"] == "repaid"))

        if repaid?, do: {"release", 0}, else: nil
    end
  end

  def outcome(_state, _g), do: nil

  # The closure names the escrow it consumed, so prior bankruptcies — the very history
  # that made this beneficiary need a sponsor — never resolve a live guarantee.
  defp failure(state, g) do
    owned(state, "bankruptcy_events", "account_id", g["beneficiary_id"])
    |> Enum.find(&(&1["guarantee_id"] == g["id"]))
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
    company = get(state, "companies", account["company_id"])
    cash = if company, do: company["cash"] - company["reserved"], else: 0
    eligible = sponsor_eligible?(state, account)

    pending =
      owned(state, "accounts", "inviter", account["id"])
      |> Enum.filter(
        &((suspended?(&1) or Finance.rate(state, &1) == 1600) and
            active(state, &1["id"]) == nil)
      )
      |> Enum.sort_by(& &1["id"])
      |> Enum.map(fn a ->
        %{
          "id" => a["id"],
          "name" => invitee_name(state, a),
          "limit" => Finance.credit_limit(state, a),
          "minimum" => @minimum_pledge,
          "maximum" => min(Finance.credit_limit(state, a), max(0, cash)),
          "enabled" => eligible and min(Finance.credit_limit(state, a), cash) >= @minimum_pledge
        }
      end)

    %{
      "pending" => pending,
      "eligible" => eligible,
      "has_sponsor" => account["inviter"] != nil,
      "active" => active(state, account["id"]),
      "pledges" =>
        entities(state, "guarantees")
        |> Map.values()
        |> Enum.filter(&(&1["sponsor_id"] == account["id"]))
        |> Enum.map(fn g ->
          case outcome(state, g) do
            nil -> Map.merge(g, %{"settlement" => nil, "settlement_amount" => 0})
            {reason, loss} -> Map.merge(g, %{"settlement" => reason, "settlement_amount" => loss})
          end
        end)
    }
  end
end
