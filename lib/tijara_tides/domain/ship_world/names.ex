defmodule TijaraTides.Domain.ShipWorld.Names do
  @moduledoc "Ship name validation against the current fleet."
  import TijaraTides.Domain.ReadState, only: [entities: 2]

  def validate(state, name, except_id \\ nil) do
    name = if is_binary(name), do: String.trim(name), else: ""

    cond do
      not TijaraTides.Domain.PlayerNames.valid?(name, 80) ->
        {:error, :ship_name_invalid}

      Enum.any?(entities(state, "ships"), fn {id, ship} ->
        id != except_id and ship["name"] == name
      end) ->
        {:error, :ship_name_taken}

      true ->
        {:ok, name}
    end
  end
end
