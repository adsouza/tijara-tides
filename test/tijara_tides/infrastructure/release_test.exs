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
          &TijaraTides.Release.migrate/0,
          &TijaraTides.Release.seed/0
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

  defp restore(key, nil), do: System.delete_env(key)
  defp restore(key, value), do: System.put_env(key, value)
end
