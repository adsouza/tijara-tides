defmodule TijaraTides.Infrastructure.SqlReplayAdvanceTest do
  # Sql.advance waits for the world owner to finish the tick it sends. A tick that
  # takes longer than the default 5 s :sys call (a commit stalled behind disk
  # flushes on a busy machine) is slow, not stuck, and must not fail the caller.
  use ExUnit.Case, async: true
  alias TijaraTides.Infrastructure.GameReadiness
  alias TijaraTides.SqlReplay, as: Sql

  defmodule SlowOwner do
    use GenServer

    def start_link(delay_ms), do: GenServer.start_link(__MODULE__, delay_ms)

    def init(delay_ms) do
      :ok = GameReadiness.register(:ready)
      {:ok, %{active: false, last_mono: 0, delay_ms: delay_ms, ticks: 0}}
    end

    def handle_info(:tick, state) do
      Process.sleep(state.delay_ms)
      {:noreply, %{state | ticks: state.ticks + 1}}
    end
  end

  @tag timeout: 30_000
  test "a tick slower than the default :sys timeout still completes the advance" do
    owner = start_supervised!({SlowOwner, 5_500})

    Sql.advance(owner, 60_000)

    assert %{ticks: 1, active: true} = :sys.get_state(owner)
  end
end
