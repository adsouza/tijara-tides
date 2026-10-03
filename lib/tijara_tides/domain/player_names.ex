defmodule TijaraTides.Domain.PlayerNames do
  @moduledoc "One validation rule for player-chosen names stored as text."

  # PostgreSQL length(text) counts code points; this storage cap applies to every name.
  @max_code_points 140

  def valid?(name, max_graphemes) do
    is_binary(name) and String.valid?(name) and name != "" and
      String.length(name) <= max_graphemes and
      length(String.codepoints(name)) <= @max_code_points and
      not String.match?(name, ~r/[\p{Cc}\p{Cf}]/u)
  end
end
