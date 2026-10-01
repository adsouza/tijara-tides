defmodule TijaraTides.Domain.MarkdownPresetWorld do
  @moduledoc "Player-owned reusable schedules; applied terms are independent copies."
  alias TijaraTides.Domain.{State, OrderBook}

  def save(state, account, cmd, new_id) do
    id = cmd["preset"] || new_id
    previous = State.get(state, "markdown_presets", id)
    name = cmd["name"]
    floor = cmd["price_floor"] || 0
    schedule = cmd["markdowns"]

    cond do
      previous && previous["account_id"] != account["id"] ->
        {:error, :exchange_freshness_invalid}

      not is_binary(name) or String.trim(name) == "" or String.length(name) > 80 ->
        {:error, :exchange_freshness_invalid}

      is_nil(schedule) or not OrderBook.schedule?(schedule) or not is_integer(floor) or
          floor not in 0..1_000_000_000_000 ->
        {:error, :exchange_freshness_invalid}

      previous == nil and
          length(State.owned(state, "markdown_presets", "account_id", account["id"])) >= 50 ->
        {:error, :exchange_freshness_invalid}

      true ->
        row = %{
          "id" => id,
          "account_id" => account["id"],
          "name" => String.trim(name),
          "markdowns" => schedule,
          "price_floor" => floor
        }

        {:ok, State.put(state, "markdown_presets", id, row), %{"preset" => id}}
    end
  end

  def delete(state, account, id) do
    account_id = account["id"]

    case State.get(state, "markdown_presets", id) do
      %{"account_id" => owner} when owner == account_id ->
        {:ok, State.delete(state, "markdown_presets", id), %{}}

      _ ->
        {:error, :exchange_freshness_invalid}
    end
  end

  def apply(state, account, cmd) do
    account_id = account["id"]

    case Map.fetch(cmd, "preset") do
      :error ->
        cmd

      {:ok, "keep"} ->
        Map.delete(cmd, "preset")

      {:ok, ""} ->
        Map.merge(cmd, %{"markdowns" => nil, "price_floor" => 0})

      {:ok, id} ->
        case State.get(state, "markdown_presets", id) do
          %{"account_id" => owner} = preset when owner == account_id ->
            Map.merge(cmd, Map.take(preset, ["markdowns", "price_floor"]))

          _ ->
            Map.put(cmd, "markdowns", false)
        end
    end
  end
end
