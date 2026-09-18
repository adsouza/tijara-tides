defmodule TijaraTides.Infrastructure.PhaseTelemetryTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Infrastructure.{Measurements, Operation}

  test "phase instrumentation preserves results and exceptions without exposing payloads" do
    id = {__MODULE__, make_ref()}
    :telemetry.attach(id, [:tijara_tides, :phase, :stop], &__MODULE__.event/4, self())
    on_exit(fn -> :telemetry.detach(id) end)

    assert Operation.run(:progression, fn ->
             Measurements.measure(:markets, fn -> {:ok, "private payload"} end)
           end) == {:ok, "private payload"}

    assert_receive {:phase, %{duration: n},
                    %{operation: :progression, phase: :markets} = metadata}

    assert n >= 0
    assert map_size(metadata) == 2

    assert_raise RuntimeError, "private failure", fn ->
      Measurements.measure(:persist, fn -> raise "private failure" end)
    end

    assert_receive {:phase, %{duration: n}, %{phase: :persist}}
    assert n >= 0
  end

  def event(_, measurements, metadata, owner) do
    if self() == owner, do: send(owner, {:phase, measurements, metadata})
  end

  test "timing all simulation phases preserves the exact transition" do
    catalogue = TijaraTides.Infrastructure.GameCatalogue.all()

    game =
      TijaraTides.Domain.Game.initialize(
        %{entities: %{}, clock_ms: 0, epoch: 1, revision: 0},
        catalogue
      )

    expected = TijaraTides.Domain.Game.advance(game, 150_000, catalogue)

    actual =
      TijaraTides.Domain.Game.advance(game, 150_000, catalogue, fn phase, fun ->
        send(self(), {:phase_name, phase})
        fun.()
      end)

    assert actual == expected

    for phase <- [
          :finance_before,
          :fleet,
          :exchange_reconcile,
          :estates,
          :auctions,
          :merchant_warehouses,
          :warehouses,
          :finance_after,
          :markets,
          :exchange,
          :berths,
          :automated_visits,
          :release_berths,
          :expire_invitations
        ] do
      assert_receive {:phase_name, ^phase}
    end

    refute_receive {:phase_name, _}
  end
end
