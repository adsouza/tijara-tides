defmodule TijaraTides.Domain.Notices do
  @moduledoc "Bounded account notices and invitation lifecycle coalescing."
  import TijaraTides.Domain.State, only: [get: 3, put: 4, delete: 3, entities: 2]

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
    retained = retained(state)

    state =
      Enum.reduce(entities(state, "notices"), state, fn {id, _}, acc ->
        if Map.has_key?(retained, id), do: acc, else: delete(acc, "notices", id)
      end)

    put_index(state, retained)
  end

  @doc "Rebuild the derived notice index without changing durable rows or recording mutations."
  def rebuild_index(state), do: put_index(state, retained(state))

  defp put_index(state, retained) do
    index =
      retained
      |> Map.values()
      |> Enum.group_by(& &1["account_id"])
      |> Map.new(fn {account, notices} ->
        {account, Enum.sort_by(notices, & &1["clock_ms"], :desc)}
      end)

    Map.put(state, :notices_by_account, index)
  end

  defp retained(state) do
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
  end
end
