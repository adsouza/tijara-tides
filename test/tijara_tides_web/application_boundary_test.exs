defmodule TijaraTidesWeb.ApplicationBoundaryTest do
  use TijaraTidesWeb.ConnCase, async: false

  defmodule UnavailableRuntime do
    def database_readiness, do: :ready
    def readiness, do: :unavailable
  end

  setup do
    previous = Application.fetch_env!(:tijara_tides, :game_runtime)
    Application.put_env(:tijara_tides, :game_runtime, UnavailableRuntime)
    on_exit(fn -> Application.put_env(:tijara_tides, :game_runtime, previous) end)
    :ok
  end

  test "HTTP readiness uses the application port without an infrastructure owner", %{conn: conn} do
    assert conn |> get("/statusz") |> json_response(503) ==
             %{"database" => "ready", "game" => "unavailable"}
  end

  test "web source cannot name an infrastructure adapter" do
    for path <- ["lib/tijara_tides_web.ex" | Path.wildcard("lib/tijara_tides_web/**/*.ex")] do
      refute File.read!(path) =~ "TijaraTides.Infrastructure", path
    end

    assert File.read!("lib/tijara_tides_web.ex") =~ "TijaraTides.UseCases"
  end
end
