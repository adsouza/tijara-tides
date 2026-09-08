defmodule TijaraTides.UseCases.CommandRequest do
  @moduledoc "Immutable command envelope. Fingerprint covers the original payload for durable replay."
  @enforce_keys [:id, :payload, :fingerprint]
  defstruct [:id, :payload, :fingerprint]
end
