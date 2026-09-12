defmodule TijaraTides.Infrastructure.Persistence.GameStore do
  @moduledoc "Atomic changed-entity writes, durable command receipts and world-owner fencing."
  alias TijaraTides.Infrastructure.Persistence.{Repo, GameRows, FinancialLedger}

  def claim(repo \\ Repo, world_id \\ "ocean", opts \\ []) do
    repo.transaction(fn ->
      TijaraTides.Infrastructure.Persistence.SchemaMaintenance.lock_claim(repo)
      repo.query!("INSERT INTO game_worlds(id) VALUES ($1) ON CONFLICT DO NOTHING", [world_id])

      %{rows: [[epoch, clock, revision]]} =
        repo.query!(
          "UPDATE game_worlds SET epoch=epoch+1 WHERE id=$1 RETURNING epoch,clock_ms,revision",
          [world_id]
        )

      FinancialLedger.audit(repo, world_id)
      entities = GameRows.load(repo, world_id, Keyword.get(opts, :wall_ms))

      %{
        epoch: epoch,
        clock_ms: clock,
        revision: revision,
        market_versions:
          Map.new(
            repo.query!("SELECT id,version FROM game_markets WHERE world_id=$1", [world_id]).rows,
            fn [id, version] -> {id, version} end
          ),
        entities: entities
      }
      |> TijaraTides.Domain.EntityIndex.rebuild()
    end)
  end

  @doc "Consistent reload without claiming ownership or incrementing the epoch."
  def reload(repo, world, previous) do
    repo.transaction(fn ->
      repo.query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")

      %{rows: rows} =
        repo.query!("SELECT epoch,clock_ms,revision FROM game_worlds WHERE id=$1", [world])

      case rows do
        [[epoch, clock, revision]] when epoch == previous.epoch ->
          FinancialLedger.audit(repo, world)
          wall_ms = System.system_time(:millisecond)
          entities = GameRows.load(repo, world, wall_ms)

          versions =
            Map.new(
              repo.query!("SELECT id,version FROM game_markets WHERE world_id=$1", [world]).rows,
              fn [id, version] -> {id, version} end
            )

          %{
            epoch: epoch,
            clock_ms: clock,
            revision: revision,
            entities: entities,
            market_versions: versions,
            identity_compacted_at: wall_ms,
            lot_allocation: Map.get(previous, :lot_allocation, [])
          }
          |> TijaraTides.Domain.EntityIndex.rebuild()

        _ ->
          repo.rollback(:ownership_lost)
      end
    end)
  end

  def commit(repo \\ Repo, world_id, epoch, before, after_state, receipt \\ nil, opts \\ []) do
    repo.transaction(
      fn ->
        %{rows: rows} =
          repo.query!("SELECT epoch FROM game_worlds WHERE id=$1 FOR UPDATE", [world_id])

        if rows != [[epoch]], do: repo.rollback(:ownership_lost)

        if receipt do
          {account, request, fingerprint, _result} = receipt

          case repo.query!(
                 "SELECT fingerprint,result FROM game_receipts WHERE world_id=$1 AND account_id=$2 AND request_id=$3",
                 [world_id, account, request]
               ).rows do
            [] -> :ok
            [[^fingerprint, result]] -> repo.rollback({:replay, result})
            _ -> repo.rollback(:request_conflict)
          end
        end

        FinancialLedger.write_lots(repo, world_id, before, after_state)
        GameRows.write(repo, world_id, before, after_state)
        FinancialLedger.post(repo, world_id, before, after_state, receipt)

        FinancialLedger.verify(
          repo,
          world_id,
          TijaraTides.Domain.ChangeSet.affected_companies(before, after_state)
        )

        if receipt do
          {account, request, fingerprint, result} = receipt

          repo.query!(
            "INSERT INTO game_receipts(world_id,account_id,request_id,fingerprint,result) VALUES ($1,$2,$3,$4,$5)",
            [world_id, account, request, fingerprint, result]
          )
        end

        repo.query!("UPDATE game_worlds SET clock_ms=$2,revision=$3 WHERE id=$1", [
          world_id,
          after_state.clock_ms,
          after_state.revision
        ])

        :ok
      end,
      opts
    )
  end

  def receipt(repo \\ Repo, world_id, account, request, fingerprint) do
    case repo.query!(
           "SELECT fingerprint,result FROM game_receipts WHERE world_id=$1 AND account_id=$2 AND request_id=$3",
           [world_id, account, request]
         ).rows do
      [] -> :new
      [[^fingerprint, result]] -> {:replay, result}
      _ -> {:error, :request_conflict}
    end
  end
end
