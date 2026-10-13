defmodule TijaraTides.Domain.ClientText do
  @moduledoc """
  Whether a client-supplied string can reach PostgreSQL. `text` and `jsonb`
  refuse U+0000 and invalid UTF-8 whatever a column's own checks say, even as a
  query parameter, so any such string must be refused before it is used. Control
  and format characters are refused with it, as player names already are.
  """
  def storable?(value),
    do:
      is_binary(value) and String.valid?(value) and not String.match?(value, ~r/[\p{Cc}\p{Cf}]/u)
end
