defmodule TijaraTides.MutationApiTest do
  use ExUnit.Case, async: true

  test "aggregate row stores are private" do
    for module <- [
          TijaraTides.Domain.Ship,
          TijaraTides.Domain.PortCargoMarket,
          TijaraTides.Domain.Account
        ] do
      Code.ensure_loaded!(module)
      refute function_exported?(module, :store, 2)
    end
  end

  test "application modules do not mutate entity maps or invoke generic domain writers" do
    for file <- Path.wildcard("lib/tijara_tides/use_cases/**/*.ex") do
      source = File.read!(file)
      refute Regex.match?(~r/\bState\.(put|delete)\(/, source), file
      refute Regex.match?(~r/\bentities\s*:/, source), file
      refute Regex.match?(~r/Map\.(put|update!?|delete)\([^\n]*\.entities\b/, source), file
    end
  end
end
