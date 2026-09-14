defmodule TijaraTides.MarketAggregateBoundaryTest do
  use ExUnit.Case, async: true

  test "auction and order rows are written only by their owning roots" do
    for {root, owned} <- [
          {"auction", ~w(auctions auction_bids)},
          {"order_book", ~w(exchange_orders exchange_trades)}
        ] do
      files = Path.wildcard("lib/tijara_tides/domain/**/*.ex")

      for file <- files,
          not String.ends_with?(file, "/#{root}.ex") do
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

            # A name bound to an owned table is a write waiting to happen.
            {:=, _, [{name, _, context}, kind]} = node, acc
            when is_atom(name) and is_atom(context) and is_binary(kind) ->
              {node, [kind | acc]}

            {:@, _, [{_attribute, _, [kind]}]} = node, acc when is_binary(kind) ->
              {node, [kind | acc]}

            node, acc ->
              {node, acc}
          end)

        assert Enum.filter(calls, &(&1 in owned)) == [], "#{file} bypasses the #{root} root"
      end
    end
  end

  test "roots expose named transitions instead of general write APIs" do
    Code.ensure_loaded!(TijaraTides.Domain.Auction)
    Code.ensure_loaded!(TijaraTides.Domain.OrderBook)
    refute function_exported?(TijaraTides.Domain.Auction, :save, 2)
    refute function_exported?(TijaraTides.Domain.OrderBook, :remove, 2)
  end
end
