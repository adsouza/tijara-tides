defmodule TijaraTides.Domain.Commands do
  alias TijaraTides.Domain.ShipWorld

  @moduledoc "Dispatch validated command shapes to the domain operation that owns their invariants."
  import TijaraTides.Domain.Account, only: [issue_invite: 3]
  import TijaraTides.Domain.Services.CompanyFormation, only: [create_company: 4]
  alias TijaraTides.Domain.{Trade}
  import TijaraTides.Domain.Fleet, only: [sail: 6]

  def execute(state, account, command, context, catalogue),
    do: execute(state, account, command, Map.put(context, :catalogue, catalogue))

  def execute(state, account, %{"action" => "locale", "locale" => locale}, _context),
    do: TijaraTides.Domain.Account.set_locale(state, account, locale)

  def execute(state, account, command, context) do
    state = TijaraTides.Domain.Services.FinancialSettlement.settle(state, [account["company_id"]])
    current_account = TijaraTides.Domain.State.get(state, "accounts", account["id"]) || account

    if TijaraTides.Domain.Guarantees.suspended?(current_account) do
      {:error, :account_suspended}
    else
      case dispatch(state, account, command, context) do
        {:ok, changed, reply} ->
          {:ok,
           TijaraTides.Domain.Warehouse.reconcile_reservations(
             changed,
             context.catalogue,
             account["company_id"]
           )
           |> TijaraTides.Domain.Services.Exchange.reconcile(account["company_id"])
           |> TijaraTides.Domain.Services.Auctions.reconcile(
             context.catalogue,
             account["company_id"]
           ), reply}

        other ->
          other
      end
    end
  end

  defp dispatch(state, account, command, context) do
    catalogue = context.catalogue

    case command do
      %{"action" => "auction_consign"} ->
        TijaraTides.Domain.Services.Auctions.consign(
          state,
          account,
          command,
          context.id,
          catalogue,
          context.auction_seed
        )

      %{"action" => "auction_revise"} ->
        TijaraTides.Domain.Services.Auctions.revise(state, account, command, catalogue)

      %{"action" => "auction_withdraw", "auction" => id} ->
        TijaraTides.Domain.Services.Auctions.withdraw_lot(state, account, id)

      %{"action" => "auction_bid"} ->
        TijaraTides.Domain.Services.Auctions.bid(state, account, command, context.id, catalogue)

      %{"action" => "auction_withdraw_bid", "auction" => id} ->
        TijaraTides.Domain.Services.Auctions.withdraw_bid(state, account, id)

      %{"action" => "exchange_place"} ->
        TijaraTides.Domain.Services.Exchange.place(state, account, command, context.id, catalogue)

      %{"action" => "exchange_amend"} ->
        TijaraTides.Domain.Services.Exchange.amend(state, account, command, catalogue)

      %{"action" => "exchange_cancel", "order" => id} ->
        TijaraTides.Domain.Services.Exchange.cancel(state, account, id)

      %{"action" => "reroute", "ship" => id, "destination" => destination, "fuel_limit" => limit} ->
        TijaraTides.Domain.Fleet.reroute(state, account, id, destination, limit, catalogue)

      %{"action" => "warehouse_reserve"} ->
        TijaraTides.Domain.Warehouse.reserve(state, account, command, context.id, catalogue)

      %{"action" => "warehouse_cancel_reservation", "reservation" => id} ->
        TijaraTides.Domain.Warehouse.cancel_reservation(state, account, id)

      %{"action" => "warehouse_renew"} ->
        TijaraTides.Domain.Warehouse.renew(state, account, command)

      %{"action" => "warehouse_auto_renew"} ->
        TijaraTides.Domain.Warehouse.renewal_settings(state, account, command)

      %{"action" => "warehouse_lease"} ->
        TijaraTides.Domain.Warehouse.lease(state, account, command, context.id, catalogue)

      %{"action" => "warehouse_release", "warehouse" => id, "blocks" => blocks} ->
        TijaraTides.Domain.Warehouse.release(state, account, id, blocks, catalogue)

      %{"action" => "warehouse_transfer"} ->
        TijaraTides.Domain.Warehouse.transfer(state, account, command, catalogue)

      %{"action" => "cancel_berth_trade", "ship" => id} ->
        TijaraTides.Domain.Services.BerthAllocation.cancel(state, account, id)

      %{"action" => "route"} ->
        ShipWorld.edit_route(state, account, command, context)

      %{"action" => "guarantee", "account" => id, "amount" => amount} ->
        TijaraTides.Domain.Guarantees.pledge(state, account, id, amount, context.id)

      %{"action" => "sell_ship", "ship" => id, "minimum" => minimum} ->
        TijaraTides.Domain.Fleet.sell(state, account, id, minimum)

      %{"action" => "borrow", "amount" => amount} ->
        TijaraTides.Domain.Services.Credit.borrow(state, account, amount, context.id)

      %{"action" => "repay", "loan" => id} ->
        TijaraTides.Domain.Services.Credit.repay(state, account, id)

      %{"action" => "recast", "loan" => id, "amount" => amount} ->
        TijaraTides.Domain.Services.Credit.recast(state, account, id, amount)

      %{"action" => "bankruptcy"} ->
        TijaraTides.Domain.Services.Bankruptcy.bankrupt(state, account)

      %{"action" => "instruction_onward", "ship" => ship, "port" => port, "onward" => onward} ->
        ShipWorld.change_onward(
          state,
          account,
          ship,
          port,
          onward,
          catalogue,
          Map.get(command, "auto_depart")
        )

      %{"action" => "instruction"} ->
        ShipWorld.add_instruction(state, account, command, context)

      %{"action" => "cancel_instruction", "instruction" => id} ->
        ShipWorld.cancel_instruction(state, account, id, catalogue)

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
        TijaraTides.Domain.Services.BerthAllocation.submit(
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
