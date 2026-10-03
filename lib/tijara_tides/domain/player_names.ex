defmodule TijaraTides.Domain.PlayerNames do
  @moduledoc "One validation rule for player-chosen names stored as text."

  # PostgreSQL length(text) counts code points. Company names leave room for hull suffixes.
  @max_code_points 140

  def valid?(name, max_graphemes, max_code_points \\ @max_code_points) do
    is_binary(name) and String.valid?(name) and name != "" and
      String.length(name) <= max_graphemes and
      length(String.codepoints(name)) <= max_code_points and
      not String.match?(name, ~r/[\p{Cc}\p{Cf}]/u)
  end
end
