defmodule TijaraTides.BrowserContractsTest do
  use ExUnit.Case, async: false
  @moduletag :browser
  alias TijaraTides.SqlReplay, as: Sql

  setup_all do
    Sql.repo()
  end

  for workflow <- ["instructions", "exchange"] do
    @tag timeout: 75_000
    test "Chromium #{workflow} serialization commits independently expected effects" do
      Sql.with_world(fn c ->
        f = TijaraTides.WebFormFixture.fixture(c)

        config = %{
          workflow: unquote(workflow),
          ship: f.ship,
          warehouse: f.warehouse,
          url: "http://127.0.0.1:" <> System.fetch_env!("TIJARA_BROWSER_TEST_PORT"),
          cookie: f.cookie
        }

        path = Path.join(System.tmp_dir!(), "tj-browser-#{c.world}.json")

        try do
          File.write!(path, Jason.encode!(config))
          File.chmod!(path, 0o600)

          {output, status} =
            System.cmd("node", ["test/browser/form_serialization.mjs", path],
              stderr_to_stdout: true
            )

          assert status == 0, output
          game = :sys.get_state(c.server).game
          assert TijaraTides.Infrastructure.GameServer.readiness(c.server) == :ready

          if unquote(workflow) == "instructions" do
            orders = Map.values(game.entities["ship_instructions"])
            assert Enum.sort(Enum.map(orders, & &1["side"])) == ["buy", "sell"]
            assert Enum.all?(orders, &(&1["quantity"] == 1 and &1["port"] == "Singapore"))
            assert Enum.all?(orders, &(&1["expires_ms"] == nil))
            assert Enum.sort(Enum.map(orders, & &1["good"])) == ["aluminium_scrap", "lumber"]
          else
            assert game.entities["exchange_orders"] == %{}
            assert game.entities["companies"][f.company]["reserved"] == 0
          end

          Sql.assert_rows(c, game)
        after
          File.rm(path)
          if Process.alive?(f.view.pid), do: GenServer.stop(f.view.pid, :normal)
        end
      end)
    end
  end
end
