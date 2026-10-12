defmodule TijaraTidesWeb.GameUI.MusicPanelTest do
  use ExUnit.Case, async: true
  alias TijaraTidesWeb.GameUI.MusicPanel

  @view %{
    private: %{"ships" => %{"c:1" => %{"id" => "c:1", "status" => "loading", "port" => "Busan"}}},
    public: %{
      "clock_ms" => 0,
      "ships" => %{"d:1" => %{"id" => "d:1", "status" => "docked", "port" => "Dubai"}}
    }
  }

  test "initial focus is the selected port after the first view" do
    assert MusicPanel.focus(nil, @view, "Tokyo") == {:port, "Tokyo"}
  end

  test "a focused ship that left the view falls back to the selected port" do
    assert MusicPanel.focus({:ship, "gone:9"}, @view, "Tokyo") == {:port, "Tokyo"}
    assert MusicPanel.focus({:ship, "c:1"}, @view, "Tokyo") == {:ship, "c:1"}
    assert MusicPanel.focus({:ship, "d:1"}, %{@view | private: nil}, "Tokyo") == {:ship, "d:1"}
    assert MusicPanel.focus({:port, "Athens"}, @view, "Tokyo") == {:port, "Athens"}
  end

  test "ships in port present their port; port focus keeps its own identifier" do
    assert MusicPanel.context(@view, {:ship, "c:1"}) == %{"context" => "port", "port" => "Busan"}
    assert MusicPanel.context(@view, {:ship, "d:1"}) == %{"context" => "port", "port" => "Dubai"}

    assert MusicPanel.context(@view, {:port, "Athens"}) == %{
             "context" => "port",
             "port" => "Athens"
           }
  end
end
