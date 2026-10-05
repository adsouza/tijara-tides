defmodule TijaraTides.Infrastructure.OperatorGrantsTest do
  use ExUnit.Case, async: false
  @moduletag :game_database
  @moduletag capture_log: true
  alias TijaraTides.Domain.AccountWorld
  alias TijaraTides.Infrastructure.GameServer
  alias TijaraTides.Infrastructure.Persistence.{GameStore, Repo}

  setup_all do
    port = System.fetch_env!("TIJARA_TEST_DB_PORT") |> String.to_integer()

    start_supervised!(
      {Repo,
       hostname: "127.0.0.1",
       port: port,
       username: "postgres",
       database: "postgres",
       ssl: false,
       pool_size: 4}
    )

    Ecto.Migrator.run(Repo, TijaraTides.TestMigrations.all(), :up, all: true, log: false)
    :ok
  end

  setup do
    world = Ecto.UUID.generate()

    server =
      start_supervised!(
        {GameServer, name: nil, enabled: true, world_id: world, tick_ms: 86_400_000}
      )

    {:ok, seed} = GameServer.seed(server)
    {:ok, %{"session" => sponsor}} = GameServer.redeem(seed, server)
    {:ok, invite} = GameServer.command(sponsor, "invite-player", %{"action" => "invite"}, server)
    {:ok, %{"session" => player}} = GameServer.redeem(invite["code"], server)
    account_id = GameServer.snapshot(player, server).private["account"]["id"]
    %{world: world, server: server, player: player, account_id: account_id, sponsor: sponsor}
  end

  test "receipt and quota survive spending, concurrent retries and restart; changed requests conflict",
       c do
    :ok = GameServer.subscribe()
    before = :sys.get_state(c.server).game

    assert {:ok, result} =
             GameServer.grant_invitations({:account, c.account_id}, 2, "grant", c.server)

    assert result["granted"] == 2
    assert result["quota_after"] == 2
    assert result["account_id"] == c.account_id
    assert_receive {:game_changed, revision}
    assert revision == before.revision + 1
    granted = :sys.get_state(c.server).game
    assert granted.clock_ms == before.clock_ms

    assert Map.get(granted.entities, "company_activity", %{}) ==
             Map.get(before.entities, "company_activity", %{})

    assert Map.get(granted.entities, "company_dormancy", %{}) ==
             Map.get(before.entities, "company_dormancy", %{})

    # An ordinary player's identical request ID does not collide with the operator receipt.
    assert {:ok, _} = GameServer.command(c.player, "grant", %{"action" => "invite"}, c.server)
    assert_receive {:game_changed, _}
    assert quota(c) == 1
    revision = :sys.get_state(c.server).game.revision

    tasks =
      for _ <- 1..4,
          do:
            Task.async(fn ->
              GameServer.grant_invitations({:account, c.account_id}, 2, "grant", c.server)
            end)

    for task <- tasks, do: assert(Task.await(task) == {:ok, result})
    assert quota(c) == 1
    assert :sys.get_state(c.server).game.revision == revision
    refute_receive {:game_changed, _}, 10

    assert {:error, :request_conflict} =
             GameServer.grant_invitations({:account, c.account_id}, 1, "grant", c.server)

    sponsor_id = GameServer.snapshot(c.sponsor, c.server).private["account"]["id"]

    assert {:error, :request_conflict} =
             GameServer.grant_invitations({:account, sponsor_id}, 2, "grant", c.server)

    stop_supervised!(GameServer)

    restarted =
      start_supervised!(
        {GameServer, name: nil, enabled: true, world_id: c.world, tick_ms: 86_400_000}
      )

    assert {:ok, ^result} =
             GameServer.grant_invitations({:account, c.account_id}, 2, "grant", restarted)

    assert GameServer.snapshot(c.player, restarted).private["account"]["invite_quota"] == 1

    assert [[^result]] =
             Repo.query!(
               "SELECT result FROM game_receipts WHERE world_id=$1 AND account_id=$2 AND request_id=$3",
               [c.world, "operator:grant_invitations", "grant"]
             ).rows
  end

  test "verified-email grants work and validation, capacity and player transport reject without writes",
       c do
    {:ok, _} =
      GameServer.email_request(c.player, "link", "player@example.com", "link", "test", c.server)

    [pending] = GameServer.email_pending(c.server)

    {:ok, _} =
      GameServer.email_redeem(
        GameServer.email_token(pending["id"]),
        GameServer.token(),
        c.player,
        c.server
      )

    assert {:ok, result} =
             GameServer.grant_invitations(
               {:email, " Player@Example.com "},
               3,
               "email-grant",
               c.server
             )

    assert result["account_id"] == c.account_id

    assert {:ok, ^result} =
             GameServer.grant_invitations(
               {:email, "player@example.com"},
               3,
               "email-grant",
               c.server
             )

    {:ok, _} = GameServer.command(c.player, "pending", %{"action" => "invite"}, c.server)
    before = :sys.get_state(c.server).game

    assert {:error, :invitation_capacity} =
             GameServer.grant_invitations({:account, c.account_id}, 1, "over-capacity", c.server)

    assert {:error, :account_not_found} =
             GameServer.grant_invitations({:email, "absent@example.com"}, 1, "absent", c.server)

    assert {:error, :invalid_invitation_count} =
             GameServer.grant_invitations({:account, c.account_id}, 4, "bad-count", c.server)

    assert {:error, :unsupported_command} =
             GameServer.command(
               c.player,
               "player-grant",
               %{"action" => "grant_invitations", "count" => 1},
               c.server
             )

    assert :sys.get_state(c.server).game == before
    assert GameServer.readiness(c.server) == :ready

    assert [] ==
             Repo.query!(
               "SELECT request_id FROM game_receipts WHERE world_id=$1 AND request_id=ANY($2)",
               [c.world, ["over-capacity", "absent", "bad-count", "player-grant"]]
             ).rows
  end

  test "fenced owner cannot grant or publish; transaction failure rolls back allowance and receipt",
       c do
    :ok = GameServer.subscribe()
    before = :sys.get_state(c.server).game
    {:ok, owner} = GameStore.claim(Repo, c.world)

    assert {:error, :ownership_lost} =
             GameServer.grant_invitations({:account, c.account_id}, 1, "fenced", c.server)

    assert :sys.get_state(c.server).game == before
    assert GameServer.readiness(c.server) == :unavailable
    refute_receive {:game_changed, _}, 10
    assert quota(c) == 0
    {:ok, changed, result} = AccountWorld.grant_invitations(owner, c.account_id, 1)

    assert_raise Postgrex.Error, fn ->
      GameStore.commit(
        Repo,
        c.world,
        owner.epoch,
        owner,
        changed,
        {"operator:grant_invitations", "rollback", nil, result}
      )
    end

    assert quota(c) == 0

    assert [] ==
             Repo.query!(
               "SELECT request_id FROM game_receipts WHERE world_id=$1 AND account_id=$2",
               [c.world, "operator:grant_invitations"]
             ).rows
  end

  defp quota(c),
    do:
      Repo.query!("SELECT invite_quota FROM game_accounts WHERE world_id=$1 AND id=$2", [
        c.world,
        c.account_id
      ]).rows
      |> hd()
      |> hd()
end
