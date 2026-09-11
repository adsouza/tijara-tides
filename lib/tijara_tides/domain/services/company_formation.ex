defmodule TijaraTides.Domain.Services.CompanyFormation do
  @moduledoc "Atomic formation across account membership and company finances."
  import TijaraTides.Domain.State, only: [get: 3, entities: 2]
  import TijaraTides.Domain.Notices, only: [notice: 4]
  alias TijaraTides.Domain.Account
  alias TijaraTides.Domain.CompanyFinance, as: Finance

  def create_company(state, account, name, context) do
    account = get(state, "accounts", account["id"])
    name = if is_binary(name), do: String.trim(name), else: ""

    cond do
      Account.suspended?(get(state, "accounts", account["id"])) ->
        {:error, :account_suspended}

      account["company_id"] != nil ->
        {:error, :company_exists}

      Account.restart_at(state, account) > state.clock_ms ->
        {:error, :bankruptcy_cooldown}

      name == "" or String.length(name) > 60 ->
        {:error, :invalid_name}

      Enum.any?(entities(state, "companies"), fn {_, c} ->
        String.downcase(c["name"]) == String.downcase(name)
      end) ->
        {:error, :name_taken}

      true ->
        id = context.id

        company = %{
          "id" => id,
          "account_id" => account["id"],
          "name" => name,
          "cash" => 0,
          "reserved" => 0,
          "profit" => 0,
          "unpaid" => 0,
          "created_ms" => state.clock_ms,
          "last_invite_year" => 0,
          "unpaid_since" => nil,
          "arrears_since" => nil,
          "bankruptcy_ms" => nil
        }

        state =
          state
          |> Finance.open(company)
          |> Account.attach_company(account["id"], id)

        state =
          notice(state, account["inviter"], "company:" <> id, "Your invitee now runs #{name}.")

        {:ok, state, %{"company_id" => id}}
    end
  end
end
