defmodule TijaraTides.AccountBoundaryTest do
  use ExUnit.Case, async: true

  test "only the Account implementation writes identity and account lifecycle rows" do
    owned = ~w(accounts sessions invitations email_requests bankruptcy_events)
    files = Path.wildcard("lib/tijara_tides/domain/**/*.ex")

    for file <- files,
        not String.contains?(file, "/account/") and not String.ends_with?(file, "/account.ex") do
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

      assert Enum.filter(calls, &(&1 in owned)) == [], "#{file} bypasses the Account aggregate"
    end
  end
end
