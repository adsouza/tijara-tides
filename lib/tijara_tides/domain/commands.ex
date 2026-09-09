defmodule TijaraTides.Domain.Commands do
  @moduledoc "Dispatch validated command shapes to the domain operation that owns their invariants."
  import TijaraTides.Domain.Accounts, only: [create_company: 6, issue_invite: 3]
  alias TijaraTides.Domain.{ShipInstructions, Trade, Trading}
  import TijaraTides.Domain.Fleet, only: [sail: 6]

  def execute(state, account, command, context, catalogue),
    do: execute(state, account, command, Map.put(context, :catalogue, catalogue))

  def execute(state, account, command, context) do
    catalogue = context.catalogue

    case command do
      %{"action" => "instruction_onward", "ship" => ship, "port" => port, "onward" => onward} ->
        ShipInstructions.change_onward(
          state,
          account,
          ship,
          port,
          onward,
          catalogue,
          Map.get(command, "auto_depart")
        )

      %{"action" => "instruction"} ->
        ShipInstructions.add(state, account, command, context)

      %{"action" => "cancel_instruction", "instruction" => id} ->
        ShipInstructions.cancel(state, account, id, catalogue)

      %{"action" => "company", "name" => name, "port" => port, "package" => package} ->
        create_company(state, account, name, port, package, context)

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
