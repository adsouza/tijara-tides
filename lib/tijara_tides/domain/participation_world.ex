defmodule TijaraTides.Domain.ParticipationWorld do
  @moduledoc "Persist qualifying economic actions inside the same world transaction."
  alias TijaraTides.Domain.{Participation, State}

  def observe(_before, changed, nil, _catalogue), do: changed

  def observe(before, changed, wall_ms, catalogue) do
    settings = Participation.settings(catalogue)

    Map.get(changed, :journal, [])
    |> Enum.drop(length(Map.get(before, :journal, [])))
    |> Enum.filter(&Participation.qualifies?(&1, settings))
    |> Enum.map(& &1.company)
    |> Enum.uniq()
    |> Enum.reduce(changed, fn company, s ->
      if State.get(s, "companies", company)["bankruptcy_ms"] == nil do
        previous = State.get(s, "company_activity", company)
        at = max(wall_ms, (previous && previous["last_action_ms"]) || wall_ms)

        State.put(s, "company_activity", company, %{
          "company_id" => company,
          "last_action_ms" => at
        })
      else
        s
      end
    end)
  end

  def index(state, wall_ms, catalogue) do
    settings = Participation.settings(catalogue)

    Enum.sum(
      for {id, company} <- State.entities(state, "companies"),
          company["bankruptcy_ms"] == nil do
        activity = State.get(state, "company_activity", id)
        Participation.weight(activity && activity["last_action_ms"], wall_ms, settings)
      end
    )
  end
end
