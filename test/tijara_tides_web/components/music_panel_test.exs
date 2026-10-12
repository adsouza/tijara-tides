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

  test "an unloading ship is a port context at its port" do
    view = put_in(@view.private["ships"]["c:1"]["status"], "unloading")
    assert MusicPanel.context(view, {:ship, "c:1"}) == %{"context" => "port", "port" => "Busan"}
  end

  test "a sailing ship is a voyage context with progress to four decimals" do
    sailing = %{
      "id" => "c:1",
      "status" => "sailing",
      "port" => "Busan",
      "destination" => "Dubai",
      "depart_ms" => 0,
      "arrive_ms" => 3_000
    }

    view = %{
      put_in(@view.private["ships"]["c:1"], sailing)
      | public: %{@view.public | "clock_ms" => 1_000}
    }

    assert %{
             "context" => "voyage",
             "ship" => "c:1",
             "origin" => "Busan",
             "destination" => "Dubai",
             "progress" => progress
           } = context = MusicPanel.context(view, {:ship, "c:1"})

    assert map_size(context) == 5
    assert progress == "0.3333"
    assert [_, decimals] = String.split(progress, ".")
    assert String.length(decimals) == 4

    late = put_in(view.public["clock_ms"], 9_000)
    assert MusicPanel.context(late, {:ship, "c:1"})["progress"] == "1.0000"
    assert MusicPanel.context(view, {:ship, "gone:9"}) == %{}
  end
end
