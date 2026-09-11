defmodule TijaraTides.CompanyFixture do
  @moduledoc "Explicit capitalized companies for trading tests; production formation grants nothing."
  use Boundary, deps: [TijaraTides.Domain, TijaraTides.Infrastructure, TijaraTides.UseCases]
  alias TijaraTides.Domain.{Accounts, Fleet, Game, Journal}

  def packages,
    do: %{
      "general" => ["freighter", "freighter", "freighter"],
      "bulk" => ["bulk", "bulk", "small_freighter"],
      "fresh" => ["reefer", "reefer", "freighter"],
      "oil" => ["tanker", "tanker", "freighter"]
    }

  def fund(state, account, port, package, catalogue) do
    company = account["company_id"]

    state =
      state
      |> TijaraTides.Domain.CompanyFinance.post(company, "test_capital", [
        {"cash_available", 20_000_000},
        {"capital", -20_000_000}
      ])

    Enum.with_index(packages()[package], 1)
    |> Enum.reduce(state, fn {class, index}, state ->
      {:ok, state, _} =
        Fleet.purchase(state, account, class, port, Fleet.classes()[class]["price"], %{
          id: company <> ":" <> to_string(index),
          catalogue: catalogue
        })

      state
    end)
  end

  def create_company(state, account, name, port, package, context) do
    with {:ok, state, reply} <- Accounts.create_company(state, account, name, context) do
      {:ok,
       fund(state, state.entities["accounts"][account["id"]], port, package, context.catalogue),
       reply}
    end
  end

  def execute(state, account, command, context, catalogue) do
    with {:ok, state, reply} <- Game.execute(state, account, command, context, catalogue) do
      {:ok,
       fund(
         state,
         state.entities["accounts"][account["id"]],
         command["port"],
         command["package"],
         catalogue
       ), reply}
    end
  end

  def command(token, request, command, server) do
    alias TijaraTides.Infrastructure.{GameServer, Persistence.GameStore}
    result = GameServer.command(token, request, command, server)

    case result do
      {:ok, %{"company_id" => company}} ->
        :sys.replace_state(server, fn state ->
          if Enum.any?(state.game.entities["ships"] || %{}, fn {_, ship} ->
               ship["company_id"] == company
             end) do
            state
          else
            account =
              Enum.find_value(state.game.entities["accounts"], fn {_, account} ->
                if account["company_id"] == company, do: account
              end)

            game =
              fund(
                Journal.clear(state.game),
                account,
                command["port"],
                command["package"],
                state.catalogue
              )

            game =
              TijaraTides.UseCases.CommitPreparation.prepare(state.game, %{
                game
                | revision: game.revision + 1
              })

            {:ok, :ok} =
              GameStore.commit(state.repo, state.world_id, game.epoch, state.game, game)

            game = TijaraTides.UseCases.CommitPreparation.accepted(game)

            %{
              state
              | game: game,
                projection: TijaraTides.UseCases.WorldProjection.build(game, state.catalogue)
            }
          end
        end)

      _ ->
        :ok
    end

    result
  end
end
