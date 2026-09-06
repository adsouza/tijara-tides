defmodule TijaraTides.Domain.World do
  @moduledoc "The empty shared world. Gameplay state will be designed separately."
  @enforce_keys [:id]
  defstruct [:id]
  @type t :: %__MODULE__{id: String.t()}
end
