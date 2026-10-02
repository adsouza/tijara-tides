defmodule TijaraTides.CommandFuzzer do
  @moduledoc "Bounded test-side command fixtures and admission ports. Never uses a live database."
  use Boundary,
    deps: [
      TijaraTides.Domain,
      TijaraTides.UseCases,
      TijaraTides.Infrastructure,
      TijaraTides.CompanyFixture,
      TijaraTides.SqlReplay
    ]

  alias TijaraTides.Domain.{Game, Journal, ReadState}
  alias TijaraTides.UseCases.{CommandRequest, GameCommands}

  def fixture(company? \\ true) do
    catalogue = TijaraTides.Infrastructure.GameCatalogue.all()
    game = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, catalogue)
    {:ok, game, _} = Game.seed_invite(game, "fixture-invite")
    {:ok, game, _} = Game.redeem(game, "fixture-invite", "session", %{id: "account", wall_ms: 0})

    if company? do
      {:ok, game, _} =
        TijaraTides.CompanyFixture.create_company(
          game,
          ReadState.get(game, "accounts", "account"),
          "Fixture",
          "Jakarta",
          "general",
          %{id: "company", catalogue: catalogue}
        )

      {Journal.clear(game), catalogue}
    else
      {Journal.clear(game), catalogue}
    end
  end

  def execute(game, catalogue, payload, id \\ "command") do
    GameCommands.execute(game, ReadState.get(game, "accounts", "account"), payload, %{
      id: id,
      wall_ms: 1,
      catalogue: catalogue,
      auction_seed: "fixture-seed"
    })
  end

  def run(game, catalogue, payload, opts \\ []) do
    request = %CommandRequest{
      id: Keyword.get(opts, :request, "request"),
      payload: payload,
      fingerprint: :crypto.hash(:sha256, :erlang.term_to_binary(payload)) |> Base.encode16()
    }

    ops = %{
      receipt: Keyword.get(opts, :receipt, fn _, _, _ -> :new end),
      commit: Keyword.get(opts, :commit, fn _, _, _ -> {:ok, :ok} end)
    }

    GameCommands.run(
      game,
      Keyword.get(opts, :session, "session"),
      request,
      %{
        id: Keyword.get(opts, :id, "allocated"),
        wall_ms: 1,
        catalogue: catalogue,
        auction_seed: "fixture-seed"
      },
      {__MODULE__.Store, ops},
      fn _, _ -> %{hash: "fixture-derived", decorate: & &1} end
    )
  end

  defmodule Store do
    @behaviour TijaraTides.UseCases.CommandStore
    def receipt(ops, account, id, fingerprint), do: ops.receipt.(account, id, fingerprint)
    def commit(ops, before, after_state, receipt), do: ops.commit.(before, after_state, receipt)
    def allocate_lot_ids(_, 0), do: []

    def allocate_lot_ids(_, count) do
      run = System.unique_integer([:positive, :monotonic])
      Enum.map(1..count, &"fixture-lot:#{run}:#{&1}")
    end

    def reload(_, game), do: {:ok, game}
    def restore(_, game, _), do: game
  end

  def outcome!({:ok, result}), do: result
  def outcome!({:ok, game, reply}), do: {game, reply}

  def outcome!({:error, reason})
      when reason not in [
             :command_failed,
             :internal_error,
             :storage_failure,
             :game_unavailable,
             :not_configured
           ],
      do: {:rejected, reason}

  def outcome!(unexpected),
    do:
      raise(ExUnit.AssertionError, message: "Unexpected command outcome: #{inspect(unexpected)}")
end
