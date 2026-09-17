defmodule TijaraTides.Infrastructure.TickSchedule do
  @moduledoc "Bounded tick pacing with hysteresis, using progression cost and mailbox scheduling delay."
  defstruct interval: 3000, slow: 0, quiet: 0, adaptive: true

  def new(opts) do
    %__MODULE__{
      interval: Keyword.get(opts, :tick_ms, 3000),
      adaptive: Keyword.get(opts, :adaptive_ticks, not Keyword.has_key?(opts, :tick_ms))
    }
  end

  def sample(%{adaptive: false} = schedule, _duration, _lag), do: schedule

  def sample(schedule, duration, lag) do
    cond do
      duration >= schedule.interval * 0.2 or lag >= 500 ->
        slow = schedule.slow + 1

        if slow >= 3,
          do: %{schedule | interval: min(15_000, schedule.interval + 1000), slow: 0, quiet: 0},
          else: %{schedule | slow: slow, quiet: 0}

      duration <= schedule.interval * 0.1 and lag <= 100 ->
        quiet = schedule.quiet + 1

        if quiet >= 10,
          do: %{schedule | interval: max(3000, schedule.interval - 1000), slow: 0, quiet: 0},
          else: %{schedule | slow: 0, quiet: quiet}

      true ->
        %{schedule | slow: 0, quiet: 0}
    end
  end
end
