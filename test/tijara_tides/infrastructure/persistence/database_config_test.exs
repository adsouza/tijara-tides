defmodule TijaraTides.Infrastructure.Persistence.DatabaseConfigTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Infrastructure.Persistence.DatabaseConfig

  test "uses verified TLS and a small pool without idle ping traffic" do
    options =
      DatabaseConfig.options(
        "postgresql://user:secret@example.test/game?sslmode=require&channel_binding=require"
      )

    assert options[:url] == "postgresql://user:secret@example.test/game"
    assert options[:ssl][:verify] == :verify_peer
    assert options[:ssl][:server_name_indication] == ~c"example.test"
    assert options[:ssl][:cacerts] != []
    assert is_function(options[:ssl][:customize_hostname_check][:match_fun], 2)
    assert options[:pool_size] == 2
    assert options[:idle_limit] == 0
    refute options[:show_sensitive_data_on_connection_error]
  end

  test "rejects unsafe query overrides without echoing credentials" do
    for suffix <- ["ssl=false", "sslmode=disable", "pool_size=1000"] do
      url = "postgresql://user:do-not-log@example.test/game?" <> suffix
      error = assert_raise ArgumentError, fn -> DatabaseConfig.options(url) end
      refute Exception.message(error) =~ "do-not-log"
    end
  end

  test "test runtime never starts the repo when a database URL is inherited" do
    config = Config.Reader.read!("config/runtime.exs", env: :test, target: :host)
    refute get_in(config, [:tijara_tides, :start_repo])
    refute Application.get_env(:tijara_tides, :start_repo)
    assert Process.whereis(TijaraTides.Infrastructure.Persistence.Repo) == nil
  end
end
