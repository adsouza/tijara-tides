defmodule TijaraTides.ReleaseTest do
  use ExUnit.Case, async: false

  test "conflicting targets fail before checking or migrating" do
    old_url = System.get_env("DATABASE_URL")
    old_local = System.get_env("TIJARA_LOCAL_DB_PORT")
    System.put_env("DATABASE_URL", "postgresql://user:secret@example.test/game")
    System.put_env("TIJARA_LOCAL_DB_PORT", "55439")

    on_exit(fn ->
      restore("DATABASE_URL", old_url)
      restore("TIJARA_LOCAL_DB_PORT", old_local)
    end)

    for operation <- [
          &TijaraTides.Release.check_database/0,
          &TijaraTides.Release.audit_ledger/0,
          &TijaraTides.Release.migrate/0,
          &TijaraTides.Release.seed/0,
          fn -> TijaraTides.Release.grant_invitations({:account, "a"}, 1, "grant") end
        ] do
      error = assert_raise RuntimeError, operation
      assert Exception.message(error) =~ "Both DATABASE_URL and TIJARA_LOCAL_DB_PORT"
      refute Exception.message(error) =~ "secret"
    end
  end

  test "shared preflight announces only the resolved target without starting a repo" do
    alias TijaraTides.Infrastructure.Persistence.Repo
    old = Application.get_env(:tijara_tides, Repo)
    old_enabled = Application.get_env(:tijara_tides, :start_repo)
    old_url = System.get_env("DATABASE_URL")
    old_local = System.get_env("TIJARA_LOCAL_DB_PORT")
    System.delete_env("DATABASE_URL")
    System.delete_env("TIJARA_LOCAL_DB_PORT")
    Application.put_env(:tijara_tides, :start_repo, true)

    Application.put_env(:tijara_tides, Repo,
      hostname: "example.test",
      database: "game",
      username: "private-user",
      password: "private-password"
    )

    on_exit(fn ->
      if old == nil,
        do: Application.delete_env(:tijara_tides, Repo),
        else: Application.put_env(:tijara_tides, Repo, old)

      Application.put_env(:tijara_tides, :start_repo, old_enabled)
      restore("DATABASE_URL", old_url)
      restore("TIJARA_LOCAL_DB_PORT", old_local)
    end)

    before = Process.whereis(Repo)

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert :ok = TijaraTides.Release.prepare_target("Launch invitation")
      end)

    assert output == "Launch invitation target: example.test:5432/game\n"
    assert Process.whereis(Repo) == before

    ExUnit.CaptureIO.capture_io(fn ->
      assert_raise RuntimeError, "Invalid invitation grant: invalid_invitation_count", fn ->
        TijaraTides.Release.grant_invitations({:account, "a"}, 4, "grant")
      end
    end)

    assert Process.whereis(Repo) == before
  end

  test "target output omits credentials and the raw URL" do
    assert TijaraTides.Release.target(
             hostname: "example.test",
             database: "game",
             username: "private-user",
             password: "private-password",
             url: "never-print"
           ) ==
             "example.test:5432/game"
  end

  test "grant script parses Mix's separator and rejects duplicate or mixed selectors before startup" do
    env = [{"MIX_ENV", "test"}, {"DATABASE_URL", nil}, {"TIJARA_LOCAL_DB_PORT", nil}]
    command = ["run", "--no-compile", "--no-start", "scripts/grant-invitations.exs"]
    arguments = ["--email", "player@example.com", "--count", "2", "--request-id", "grant"]

    for separator <- [[], ["--"]] do
      {output, status} =
        System.cmd("mix", command ++ separator ++ arguments, env: env, stderr_to_stdout: true)

      assert status != 0
      assert output =~ "Game storage is not configured"
      refute output =~ "Usage:"
    end

    for extra <- [["--account", "a"], ["--count", "1"], ["--request-id", "duplicate"]] do
      {output, status} =
        System.cmd("mix", command ++ ["--"] ++ arguments ++ extra,
          env: env,
          stderr_to_stdout: true
        )

      assert status != 0
      assert output =~ "Usage:"
      refute output =~ "Game storage is not configured"
    end
  end

  defp restore(key, nil), do: System.delete_env(key)
  defp restore(key, value), do: System.put_env(key, value)
end
