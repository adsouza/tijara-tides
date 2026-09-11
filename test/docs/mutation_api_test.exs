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

  test "aggregate implementations never invoke coordinating services" do
    files =
      Path.wildcard("lib/tijara_tides/domain/{account,company_finance,ship,port_cargo_market}.ex") ++
        Path.wildcard(
          "lib/tijara_tides/domain/{account,company_finance,ship,port_cargo_market}/**/*.ex"
        )

    for file <- files do
      ast = file |> File.read!() |> Code.string_to_quoted!()

      Macro.prewalk(ast, fn
        {:__aliases__, _, parts} = node ->
          refute :Services in parts, "#{file} invokes orchestration from an aggregate"
          node

        node ->
          node
      end)
    end
  end

  test "application modules and coordinating services cannot use generic writers" do
    files =
      Path.wildcard("lib/tijara_tides/use_cases/**/*.ex") ++
        Path.wildcard("lib/tijara_tides/domain/services/**/*.ex")

    for file <- files do
      ast = file |> File.read!() |> Code.string_to_quoted!()

      Macro.prewalk(ast, fn
        {{:., _, [{:__aliases__, _, parts}, operation]}, _, _} = node ->
          refute List.last(parts) == :State and operation in [:put, :delete, :evict], file
          node

        {operation, _, _} = node when operation in [:put, :delete, :evict] ->
          flunk("#{file} invokes an imported generic writer: #{operation}")
          node

        {:%{}, _, fields} = node ->
          pairs =
            case fields do
              [{:|, _, [_, updates]}] -> updates
              _ -> fields
            end

          refute Enum.any?(pairs, &match?({:entities, _}, &1)), file
          node

        {operation, _, args} = node when operation in [:put_in, :update_in, :get_and_update_in] ->
          refute Macro.to_string(args) =~ ":entities", file
          node

        node ->
          node
      end)
    end
  end
end
