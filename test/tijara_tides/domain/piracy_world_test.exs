defmodule TijaraTides.Domain.PiracyWorldTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{Game, Piracy, PiracyWorld, Visibility}
  alias TijaraTides.Infrastructure.GameCatalogue

  defp at(ms), do: %{entities: %{}, clock_ms: ms, epoch: 1, revision: 0}

  defp first_campaign(model) do
    Enum.find_value(1..1_000, fn slot ->
      Enum.find_value(Enum.sort(Map.keys(model["zones"])), &Piracy.campaign(&1, slot, model))
    end)
  end

  test "refresh projects announced campaigns and drops ended ones" do
    catalogue = GameCatalogue.all()
    c = first_campaign(Piracy.model(catalogue))

    announced = PiracyWorld.refresh(at(c["announced_ms"]), catalogue)
    assert PiracyWorld.public(announced)[c["id"]] == c

    ended = PiracyWorld.refresh(%{announced | clock_ms: c["until_ms"]}, catalogue)
    refute Map.has_key?(PiracyWorld.public(ended), c["id"])
  end

  test "a catalogue without piracy projects nothing" do
    assert PiracyWorld.public(PiracyWorld.refresh(at(123_456_789), %{})) == %{}
  end

  test "initialization refreshes campaigns and publishes them" do
    catalogue = GameCatalogue.all()
    c = first_campaign(Piracy.model(catalogue))
    state = Game.initialize(at(c["starts_ms"]), catalogue)

    assert Visibility.public(state, catalogue)["piracy"][c["id"]] == c
  end
end
