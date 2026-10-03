defmodule TijaraTides.OwnLog do
  @moduledoc """
  Log capture limited to the calling process.

  `ExUnit.CaptureLog` also collects messages that concurrent async tests log
  during the capture, so a count over its output is flaky. This tags the
  caller's Logger metadata with a unique marker and keeps only entries that
  carry it. Spawned processes do not inherit Logger metadata, so their entries
  are dropped too; use `capture_log/2` and partial matches for those.
  """
  use Boundary
  import ExUnit.CaptureLog

  @doc "Runs `fun` and returns the formatted entries this process logged, in order."
  def capture(fun) do
    marker = "own-log-#{System.unique_integer([:positive])}"
    previous = Logger.metadata()[:own_log]
    Logger.metadata(own_log: marker)

    try do
      # A NUL separator survives multi-line messages such as stack traces.
      capture_log([format: "\0$metadata$message\n", metadata: [:own_log]], fun)
      |> String.split("\0", trim: true)
      |> Enum.flat_map(fn entry ->
        case String.split(entry, "own_log=#{marker} ", parts: 2) do
          ["", message] -> [message]
          _ -> []
        end
      end)
    after
      Logger.metadata(own_log: previous)
    end
  end
end
