defmodule TijaraTides.CompanyFinanceBoundaryTest do
  use ExUnit.Case, async: true

  test "only the CompanyFinance implementation writes financial rows" do
    owned = ~w(companies loans loan_installments operating_bills guarantees)
    files = Path.wildcard("lib/tijara_tides/domain/**/*.ex")

    for file <- files,
        not String.ends_with?(file, "/state.ex") and
          not String.contains?(file, "/company_finance/") and
          not String.ends_with?(file, "/company_finance.ex") do
      {_ast, calls} =
        file
        |> File.read!()
        |> Code.string_to_quoted!()
        |> Macro.prewalk([], fn
          {operation, _, [_state, kind | _]} = node, acc
          when operation in [:put, :delete] and is_binary(kind) ->
            {node, [kind | acc]}

          {{:., _, [_module, operation]}, _, [_state, kind | _]} = node, acc
          when operation in [:put, :delete] and is_binary(kind) ->
            {node, [kind | acc]}

          {operation, _, [kind | _]} = node, acc
          when operation in [:put, :delete] and is_binary(kind) ->
            {node, [kind | acc]}

          node, acc ->
            {node, acc}
        end)

      assert Enum.filter(calls, &(&1 in owned)) == [],
             "#{file} bypasses the CompanyFinance aggregate"
    end
  end
end
