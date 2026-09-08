defmodule TijaraTides.Domain.Notices do
  @moduledoc "Bounded account notices and invitation lifecycle coalescing."
  import TijaraTides.Domain.State, only: [get: 3, put: 4, entities: 2]

  def notice(state, nil, _id, _text), do: state

  def notice(state, account, id, text) do
    state
    |> put("notices", id, %{
      "account_id" => account,
      "text" => text,
      "clock_ms" => state.clock_ms
    })
    |> prune_notices()
  end

  # Replace pending invitation notices with company announcements, including
  # notices persisted before this replacement rule was introduced.
  # Retain the newest 100 notices per account, including across restarts.
  def prune_notices(state) do
    retained =
      entities(state, "notices")
      |> Enum.reject(fn
        {"accepted:" <> invitee_id, _notice} ->
          case get(state, "accounts", invitee_id) do
            %{"company_id" => company_id} when is_binary(company_id) ->
              get(state, "notices", "company:" <> company_id) != nil

            _ ->
              false
          end

        _ ->
          false
      end)
      |> Enum.group_by(fn {_, notice} -> notice["account_id"] end)
      |> Enum.flat_map(fn {_, notices} ->
        notices
        |> Enum.sort_by(fn {id, notice} -> {-notice["clock_ms"], id} end)
        |> Enum.take(100)
      end)
      |> Map.new()

    index =
      retained
      |> Map.values()
      |> Enum.group_by(& &1["account_id"])
      |> Map.new(fn {account, notices} ->
        {account, Enum.sort_by(notices, & &1["clock_ms"], :desc)}
      end)

    state
    |> Map.put(:entities, Map.put(state.entities, "notices", retained))
    |> Map.put(:notices_by_account, index)
  end
end
