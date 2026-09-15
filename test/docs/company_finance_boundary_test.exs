defmodule TijaraTides.CompanyFinanceBoundaryTest do
  use ExUnit.Case, async: true

  test "only the CompanyFinance implementation writes financial rows" do
    owned = ~w(companies loans loan_installments operating_bills guarantees)
    files = Path.wildcard("lib/tijara_tides/domain/**/*.ex")

    for file <- files,
        not String.ends_with?(file, "/state.ex") and
          not String.contains?(file, "/company_finance_world/") and
          not String.ends_with?(file, "/company_finance_world.ex") do
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

  test "financial transitions cannot use world state, indexes or row codecs" do
    for file <-
          ~w(lib/tijara_tides/domain/company_finance.ex lib/tijara_tides/domain/company_finance/transition.ex lib/tijara_tides/domain/company_finance/loan_actions.ex) do
      ast = file |> File.read!() |> Code.string_to_quoted!()

      Macro.prewalk(ast, fn
        {:__aliases__, _, parts} = node ->
          refute Enum.any?(
                   parts,
                   &(&1 in [
                       :State,
                       :ReadState,
                       :EntityIndex,
                       :ChangeSet,
                       :Rows,
                       :CompanyFinanceWorld,
                       :Notices
                     ])
                 )

          node

        {{:., _, [_module, function]}, _, _} = node when function in [:from_row, :to_row] ->
          flunk("#{file} round-trips typed finance through rows")
          node

        node ->
          node
      end)
    end
  end
end
