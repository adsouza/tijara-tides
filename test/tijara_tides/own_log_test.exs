defmodule TijaraTides.OwnLogTest do
  # Concurrent async tests log into every active capture; OwnLog must keep only
  # the caller's entries, including multi-line ones.
  use ExUnit.Case, async: true
  require Logger

  test "keeps the caller's entries and drops another process's during the capture" do
    log =
      TijaraTides.OwnLog.capture(fn ->
        Logger.error("own failure\n    frame one")
        task = Task.async(fn -> Logger.error("concurrent failure") end)
        Task.await(task)
        Logger.error("own second")
      end)

    assert log == ["own failure\n    frame one\n", "own second\n"]
    assert Logger.metadata()[:own_log] == nil
  end
end
