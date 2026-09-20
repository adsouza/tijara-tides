defmodule TijaraTides.Infrastructure.OperationBoundaryTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  alias TijaraTides.Infrastructure.OperationBoundary, as: Boundary

  defp state, do: %{status: :ready, active: true, game: :original}
  defp accept(state, outcome), do: %{state | game: outcome.game}
  defp refresh(state, game), do: %{state | game: game}
  defp call(result), do: Boundary.call(:command, state(), fn -> result end, &accept/2, &refresh/2)

  test "success, rejection, refreshed conflict and halt retain distinct responses" do
    assert {:reply, {:ok, :done}, %{game: :committed}} =
             call({:ok, %{reply: :done, game: :committed}})

    assert {:reply, {:error, :insufficient_funds}, original} = call({:error, :insufficient_funds})
    assert original == state()

    log =
      capture_log(fn ->
        assert {:reply, {:error, :command_failed}, original} = call({:error, :command_failed})
        assert original == state()
      end)

    assert log =~ "reason=command_failed"

    assert {:reply, {:error, :market_busy}, %{game: :fresh, active: true, status: :ready}} =
             call({:error, :market_busy, :fresh})

    assert {:reply, {:error, :ownership_lost},
            %{game: :original, active: false, status: :unavailable}} =
             call({:halt, :ownership_lost})
  end

  test "storage and internal exceptions pause calls without accepting a candidate" do
    for {error, reason} <- [
          {%Postgrex.Error{message: "storage failed"}, :storage_unavailable},
          {%DBConnection.ConnectionError{message: "connection failed"}, :storage_unavailable},
          {ArgumentError.exception("invalid state"), :internal_error}
        ] do
      capture_log(fn ->
        assert {:reply, {:error, ^reason},
                %{game: :original, active: false, status: :unavailable}} =
                 Boundary.call(
                   :command,
                   state(),
                   fn -> raise error end,
                   fn _, _ -> flunk("must not accept") end,
                   fn _, _ -> flunk("must not refresh") end
                 )
      end)
    end
  end

  test "a read chooses its own safe response and logs an exception exactly once" do
    handler = "boundary-#{System.unique_integer([:positive])}"
    pid = self()

    :ok =
      :telemetry.attach(
        handler,
        [:tijara_tides, :operation, :exception],
        fn _, _, metadata, _ ->
          if self() == pid, do: send(pid, {:exception, metadata.operation})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    capture_log(fn ->
      assert {:error, :report_unavailable} =
               Boundary.run(:report_query, fn -> raise "query failed" end, fn :internal_error ->
                 {:error, :report_unavailable}
               end)
    end)

    assert_received {:exception, :report_query}
    refute_received {:exception, :report_query}
  end

  test "acceptance failure after a successful commit still pauses the owner" do
    capture_log(fn ->
      assert {:reply, {:error, :internal_error},
              %{game: :original, active: false, status: :unavailable}} =
               Boundary.call(
                 :command,
                 state(),
                 fn -> {:ok, %{reply: :done, game: :committed}} end,
                 fn _, _ -> raise ArgumentError, "projection failed after commit" end,
                 &refresh/2
               )
    end)
  end

  test "exits and throws are not converted into recoverable responses" do
    recover = fn _ -> flunk("must preserve OTP failure semantics") end

    capture_log(fn ->
      assert catch_exit(Boundary.run(:command, fn -> exit(:shutdown) end, recover)) == :shutdown
      assert catch_throw(Boundary.run(:command, fn -> throw(:stop) end, recover)) == :stop
    end)
  end
end
