defmodule TijaraTides.Domain.PiracyWorld do
  @moduledoc "Durable public projection of announced and running pirate campaigns; rolls read the pure model."
  alias TijaraTides.Domain.{Piracy, State}

  def refresh(state, catalogue) do
    desired = Piracy.campaigns(state.clock_ms, Piracy.model(catalogue))

    state =
      Enum.reduce(State.entities(state, "piracy_campaigns"), state, fn {id, _}, s ->
        if Map.has_key?(desired, id), do: s, else: State.delete(s, "piracy_campaigns", id)
      end)

    Enum.reduce(desired, state, fn {id, row}, s -> State.put(s, "piracy_campaigns", id, row) end)
  end

  def public(state), do: State.entities(state, "piracy_campaigns")
end
