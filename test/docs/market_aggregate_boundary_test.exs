defmodule TijaraTides.MarketAggregateBoundaryTest do
  use ExUnit.Case, async: true

  test "auction and order rows are written only by their owning roots" do
    for {root, owned} <- [
          {"auction_world", ~w(auctions auction_bids)},
          {"order_book_world", ~w(exchange_orders exchange_trades)}
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

  test "the typed auction root cannot depend on world access or row codecs" do
    files =
      ~w(lib/tijara_tides/domain/auction.ex lib/tijara_tides/domain/auction/bid.ex lib/tijara_tides/domain/order_book.ex)

    forbidden = ~w(State ReadState EntityIndex ChangeSet AuctionWorld OrderBookWorld Rows BidRows)

    for file <- files do
      {_ast, dependencies} =
        file
        |> File.read!()
        |> Code.string_to_quoted!()
        |> Macro.prewalk([], fn
          {:__aliases__, _, parts} = node, acc -> {node, Enum.map(parts, &to_string/1) ++ acc}
          node, acc -> {node, acc}
        end)

      assert Enum.filter(dependencies, &(&1 in forbidden)) == [], file
    end

    Code.ensure_loaded!(TijaraTides.Domain.Auction)
    refute function_exported?(TijaraTides.Domain.Auction, :from_row, 1)
    refute function_exported?(TijaraTides.Domain.Auction, :to_row, 1)
  end

  test "roots expose named transitions instead of general write APIs" do
    Code.ensure_loaded!(TijaraTides.Domain.Auction)
    Code.ensure_loaded!(TijaraTides.Domain.OrderBook)
    Code.ensure_loaded!(TijaraTides.Domain.AuctionWorld)
    refute function_exported?(TijaraTides.Domain.Auction, :save, 2)
    refute function_exported?(TijaraTides.Domain.Auction, :put_bid, 2)
    refute function_exported?(TijaraTides.Domain.Auction, :delete_bid, 2)
    refute function_exported?(TijaraTides.Domain.OrderBook, :remove, 2)
    refute function_exported?(TijaraTides.Domain.AuctionWorld, :save, 2)
    refute function_exported?(TijaraTides.Domain.AuctionWorld, :put_bid, 2)
  end
end
