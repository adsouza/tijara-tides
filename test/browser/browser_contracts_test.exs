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
          url: url(),
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

  defp url do
    {:ok, {ip, port}} = TijaraTidesWeb.Endpoint.server_info(:http)
    "http://#{:inet.ntoa(ip)}:#{port}"
  end

  @tag timeout: 90_000
  test "Chromium berth follows committed handling and survives lifecycle changes" do
    Sql.with_world(fn c ->
      f = TijaraTides.WebFormFixture.fixture(c)

      Sql.command(c, f.token, "berth-load", %{
        "action" => "buy",
        "ship" => f.ship,
        "good" => "lumber",
        "quantity" => 80,
        "limit" => 1_000_000,
        "destination" => "Singapore"
      })

      path = Path.join(System.tmp_dir!(), "tj-berth-#{c.world}.json")
      state = :sys.get_state(c.server)
      ship = state.game.entities["ships"][f.ship]
      volume = state.catalogue["goods"]["lumber"]["volume_l"]

      try do
        File.write!(
          path,
          Jason.encode!(%{
            ship: f.ship,
            url: url(),
            cookie: f.cookie,
            start: state.game.clock_ms,
            volume: 80 * volume,
            cargoVolume: 85 * volume,
            capacity: TijaraTides.Domain.Fleet.classes()[ship["class"]]["volume"]
          })
        )

        File.chmod!(path, 0o600)

        port =
          Port.open({:spawn_executable, System.find_executable("node")}, [
            :binary,
            :exit_status,
            :stderr_to_stdout,
            {:line, 8192},
            {:args, ["test/browser/ship_berth.mjs", path]}
          ])

        assert {:ok, output} = berth_runner(port, c, f, ""), "browser berth failed"
        assert output =~ "Berth browser contracts passed"
        game = :sys.get_state(c.server).game
        assert game.entities["ships"][f.ship]["status"] == "sailing"
        Sql.assert_rows(c, game)
      after
        File.rm(path)
        if Process.alive?(f.view.pid), do: GenServer.stop(f.view.pid, :normal)
      end
    end)
  end

  defp berth_runner(port, c, f, output) do
    receive do
      {^port, {:data, {_, "BERTH_ADVANCE"}}} ->
        Sql.advance(c.server, 60_000)
        berth_runner(port, c, f, output)

      {^port, {:data, {_, "BERTH_UNLOAD"}}} ->
        Sql.command(c, f.token, "berth-unload", %{
          "action" => "warehouse_transfer",
          "ship" => f.ship,
          "warehouse" => f.warehouse,
          "side" => "store",
          "good" => "lumber",
          "quantity" => 80
        })

        berth_runner(port, c, f, output)

      {^port, {:data, {_, "BERTH_SAIL"}}} ->
        Sql.advance(c.server, 60_000)

        Sql.command(c, f.token, "berth-sail", %{
          "action" => "sail",
          "ship" => f.ship,
          "destination" => "Singapore",
          "fuel_limit" => 1_000_000
        })

        berth_runner(port, c, f, output)

      {^port, {:data, {_, line}}} ->
        berth_runner(port, c, f, output <> line <> "\n")

      {^port, {:exit_status, 0}} ->
        {:ok, output}

      {^port, {:exit_status, status}} ->
        flunk("Berth browser exited #{status}:\n#{output}")
    after
      70_000 ->
        Port.close(port)
        flunk("Berth browser timed out:\n#{output}")
    end
  end
end
