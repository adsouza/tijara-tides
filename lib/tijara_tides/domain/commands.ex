defmodule TijaraTides.Domain.Commands do
  @moduledoc "Dispatch validated command shapes to the domain operation that owns their invariants."
  import TijaraTides.Domain.Accounts, only: [create_company: 4, issue_invite: 3]
  alias TijaraTides.Domain.{Finance, Ship, Trade, Trading}
  import TijaraTides.Domain.Fleet, only: [sail: 6]

  def execute(state, account, command, context, catalogue),
    do: execute(state, account, command, Map.put(context, :catalogue, catalogue))

  def execute(state, account, command, context) do
    state = Finance.settle(state)
    current_account = TijaraTides.Domain.State.get(state, "accounts", account["id"]) || account

    if TijaraTides.Domain.Guarantees.suspended?(current_account) do
      {:error, :account_suspended}
    else
      dispatch(state, account, command, context)
    end
  end

  defp dispatch(state, account, command, context) do
    catalogue = context.catalogue

    case command do
      %{"action" => "route"} ->
        Ship.edit_route(state, account, command, context)

      %{"action" => "guarantee", "account" => id, "amount" => amount} ->
        TijaraTides.Domain.Guarantees.pledge(state, account, id, amount, context.id)

      %{"action" => "sell_ship", "ship" => id, "minimum" => minimum} ->
        TijaraTides.Domain.Fleet.sell(state, account, id, minimum)

      %{"action" => "borrow", "amount" => amount} ->
        Finance.borrow(state, account, amount, context.id)

      %{"action" => "repay", "loan" => id} ->
        Finance.repay(state, account, id)

      %{"action" => "recast", "loan" => id, "amount" => amount} ->
        Finance.recast(state, account, id, amount)

      %{"action" => "bankruptcy"} ->
        Finance.bankrupt(state, account)

      %{"action" => "instruction_onward", "ship" => ship, "port" => port, "onward" => onward} ->
        Ship.change_onward(
          state,
          account,
          ship,
          port,
          onward,
          catalogue,
          Map.get(command, "auto_depart")
        )

      %{"action" => "instruction"} ->
        Ship.add_instruction(state, account, command, context)

      %{"action" => "cancel_instruction", "instruction" => id} ->
        Ship.cancel_instruction(state, account, id, catalogue)

      %{"action" => "company", "name" => name} ->
        create_company(state, account, name, context)

      %{
        "action" => "purchase_ship",
        "class" => class,
        "port" => port,
        "price_limit" => price_limit
      } ->
        TijaraTides.Domain.Fleet.purchase(state, account, class, port, price_limit, context)

      %{"action" => "invite"} ->
        issue_invite(state, account, context)

      %{
        "action" => action,
        "ship" => ship_id,
        "good" => good,
        "quantity" => quantity,
        "limit" => limit
      }
      when action in ["buy", "sell"] ->
        Trading.execute(
          state,
          account,
          %Trade{
            side: action,
            ship_id: ship_id,
            good: good,
            quantity: quantity,
            limit: limit,
            destination: command["destination"]
          },
          catalogue
        )

      %{"action" => "sail", "ship" => id, "destination" => destination, "fuel_limit" => limit} ->
        sail(state, account, id, destination, limit, catalogue)

      _ ->
        {:error, :unsupported_command}
    end
  end
end
