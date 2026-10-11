defmodule TijaraTides.OwnLogTest do
  # Concurrent async tests log into every active capture; OwnLog must keep only
  # the caller's entries, including multi-line ones.
  # The colour regression changes global formatter configuration.
  use ExUnit.Case, async: false
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

  test "returns plain entries when the default logger formatter enables colours" do
    previous = Application.fetch_env(:logger, :default_formatter)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:logger, :default_formatter, value)
        :error -> Application.delete_env(:logger, :default_formatter)
      end
    end)

    formatter = Application.get_env(:logger, :default_formatter, [])

    Application.put_env(
      :logger,
      :default_formatter,
      Keyword.put(formatter, :colors, enabled: true)
    )

    raw = ExUnit.CaptureLog.capture_log([format: "$message\n"], fn -> Logger.error("raw") end)
    assert raw =~ IO.ANSI.red()

    log =
      TijaraTides.OwnLog.capture(fn ->
        Logger.warning("own warning")
        Logger.error("own error\n    frame one")
      end)

    assert log == ["own warning\n", "own error\n    frame one\n"]
    assert Logger.metadata()[:own_log] == nil
  end
end
