defmodule TijaraTides.Release.DatabaseWaitTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Release.DatabaseWait
  import ExUnit.CaptureLog

  defp timer do
    Process.put(:wait_clock, 0)

    [
      clock: fn -> Process.get(:wait_clock) end,
      sleep: fn ms -> Process.put(:wait_clock, Process.get(:wait_clock) + ms) end
    ]
  end

  test "connection failures may be returned or raised before readiness succeeds" do
    Process.put(:attempts, 0)

    check = fn timeout ->
      assert timeout == 5000
      n = Process.get(:attempts)
      Process.put(:attempts, n + 1)

      case n do
        0 -> {:error, %DBConnection.ConnectionError{message: "private credentials"}}
        1 -> raise DBConnection.ConnectionError, "private credentials"
        2 -> {:ok, %{rows: [[1]]}}
      end
    end

    log = capture_log(fn -> assert :ok == DatabaseWait.await(nil, timer() ++ [check: check]) end)
    assert Process.get(:attempts) == 3
    assert Process.get(:wait_clock) == 2000
    refute log =~ "private credentials"
  end

  test "deadline includes query time and caps the final query timeout" do
    check = fn timeout ->
      assert timeout == 500
      Process.put(:wait_clock, Process.get(:wait_clock) + timeout)
      {:error, %DBConnection.ConnectionError{message: "private credentials"}}
    end

    error =
      assert_raise RuntimeError, fn ->
        DatabaseWait.await(nil, timer() ++ [timeout: 500, check: check])
      end

    assert Exception.message(error) =~ "no migrations attempted"
    refute Exception.message(error) =~ "private credentials"
    assert Process.get(:wait_clock) == 500
  end

  test "SQL and unexpected errors fail immediately" do
    for {type, check} <- [
          {Postgrex.Error, fn _ -> {:error, %Postgrex.Error{message: "SQL failure"}} end},
          {ArgumentError, fn _ -> raise ArgumentError, "configuration failure" end}
        ] do
      assert_raise type, fn -> DatabaseWait.await(nil, timer() ++ [check: check]) end
      assert Process.get(:wait_clock) == 0
    end
  end

  test "fast failures stop at the deadline without another probe" do
    Process.put(:attempts, 0)

    check = fn _ ->
      Process.put(:attempts, Process.get(:attempts) + 1)
      {:error, %DBConnection.ConnectionError{message: "unavailable"}}
    end

    capture_log(fn ->
      assert_raise RuntimeError, fn ->
        DatabaseWait.await(nil, timer() ++ [timeout: 2500, check: check])
      end
    end)

    assert Process.get(:attempts) == 3
    assert Process.get(:wait_clock) == 2500
  end
end
