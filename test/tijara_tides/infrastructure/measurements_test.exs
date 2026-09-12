defmodule TijaraTides.Infrastructure.MeasurementsTest do
  use ExUnit.Case, async: false
  alias TijaraTides.Infrastructure.Measurements

  setup do
    handler = "measurements-#{System.unique_integer([:positive])}"
    pid = self()

    :ok =
      :telemetry.attach_many(
        handler,
        for(event <- [:owner, :tick, :conflict], do: [:tijara_tides, event]),
        fn event, measurements, metadata, _ ->
          if self() == pid, do: send(pid, {:metric, event, measurements, metadata})
        end,
        nil
      )

    previous = Application.get_env(:tijara_tides, :game_server)

    on_exit(fn ->
      :telemetry.detach(handler)

      if previous,
        do: Application.put_env(:tijara_tides, :game_server, previous),
        else: Application.delete_env(:tijara_tides, :game_server)
    end)

    :ok
  end

  test "mailbox sampling does not call a busy owner" do
    pid =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    on_exit(fn -> Process.exit(pid, :kill) end)
    send(pid, :queued_one)
    send(pid, :queued_two)
    Application.put_env(:tijara_tides, :game_server, pid)
    Measurements.poll_owner()
    assert_received {:metric, [:tijara_tides, :owner], %{mailbox_depth: 2}, %{}}
  end

  test "tick lag measures scheduled lateness, not elapsed world time" do
    Measurements.tick_lag(1000, 1250)
    assert_received {:metric, [:tijara_tides, :tick], %{lag: 250}, %{}}
    Measurements.tick_lag(1000, 990)
    assert_received {:metric, [:tijara_tides, :tick], %{lag: 0}, %{}}
    Measurements.tick_lag(nil, 1250)
    refute_received {:metric, _, _, _}
  end

  defmodule Store do
    def reload(_, game), do: {:ok, game}
  end

  test "retry exhaustion records two actual retries and one exhausted operation" do
    assert {:error, :market_busy, _} =
             TijaraTides.UseCases.CommitExecutor.replan(
               %{entities: %{}},
               {Store, nil},
               fn _ -> {:halt, :market_conflict} end
             )

    for _ <- 1..2 do
      assert_received {:metric, [:tijara_tides, :conflict], %{count: 1}, %{outcome: :retry}}
    end

    assert_received {:metric, [:tijara_tides, :conflict], %{count: 1}, %{outcome: :exhausted}}
    refute_received {:metric, _, _, _}
  end
end
