defmodule TijaraTides.Domain.WeatherWorld do
  @moduledoc "Durable bounded current regional warnings; voyage timelines belong to ships."
  alias TijaraTides.Domain.{State, Weather}

  def refresh(state, catalogue) do
    desired = Weather.active(state.clock_ms, Weather.model(catalogue))

    state =
      Enum.reduce(State.entities(state, "weather"), state, fn {id, _}, s ->
        if Map.has_key?(desired, id), do: s, else: State.delete(s, "weather", id)
      end)

    Enum.reduce(desired, state, fn {id, row}, s -> State.put(s, "weather", id, row) end)
  end

  def public(state), do: State.entities(state, "weather")
end
