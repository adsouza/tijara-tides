defmodule TijaraTides.UseCases.WorldCommands do
  @moduledoc "Future command boundary. No gameplay commands are implemented yet."
  alias TijaraTides.Domain.World

  @spec execute(World.t(), String.t(), term()) :: {:error, :unsupported_command}
  def execute(%World{}, _player_id, _command), do: {:error, :unsupported_command}
end
