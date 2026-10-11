defmodule TijaraTides.Infrastructure.PiracyConfigurationTest do
  use ExUnit.Case, async: false
  alias TijaraTides.Infrastructure.GameCatalogue

  test "catalogue loading fails before gameplay when the runtime attack salt is absent or short" do
    previous = Application.get_env(:tijara_tides, :piracy)
    on_exit(fn -> Application.put_env(:tijara_tides, :piracy, previous) end)

    for override <- [%{}, %{"salt" => "short"}] do
      Application.put_env(:tijara_tides, :piracy, override)
      assert_raise ArgumentError, ~r/private salt/, &GameCatalogue.all/0
    end
  end
end
