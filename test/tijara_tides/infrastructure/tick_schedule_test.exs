defmodule TijaraTides.Infrastructure.TickScheduleTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Infrastructure.TickSchedule

  defp samples(schedule, count, duration, lag),
    do: Enum.reduce(1..count, schedule, fn _, s -> TickSchedule.sample(s, duration, lag) end)

  test "three-second default tolerates brief spikes and requires sustained recovery" do
    initial = TickSchedule.new([])
    assert initial.interval == 3000
    spike = samples(initial, 2, 700, 0)
    assert spike.interval == 3000
    assert TickSchedule.sample(spike, 90, 0).slow == 0
    slow = samples(initial, 3, 700, 0)
    assert slow.interval == 4000
    assert samples(slow, 9, 90, 0).interval == 4000
    assert samples(slow, 10, 90, 0).interval == 3000
  end

  test "mailbox delay slows ticks independently of progression cost and bounds hold" do
    initial = TickSchedule.new([])
    assert samples(initial, 3, 90, 600).interval == 4000
    ceiling = samples(initial, 100, 5000, 600)
    assert ceiling.interval == 15_000
    assert samples(ceiling, 150, 90, 0).interval == 3000
    assert samples(initial, 20, 400, 200).interval == 3000
  end

  test "explicit intervals stay fixed for deterministic tests and benchmarks" do
    fixed = TickSchedule.new(tick_ms: 86_400_000)
    assert samples(fixed, 100, 5000, 5000) == fixed
  end
end
