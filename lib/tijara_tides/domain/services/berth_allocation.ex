defmodule TijaraTides.Domain.Services.BerthAllocation do
  alias TijaraTides.Domain.PortBerthsWorld
  alias TijaraTides.Domain.ShipWorld
  @moduledoc "Coordinate persisted ship queue tickets, admission, and delayed manual trades."
  alias TijaraTides.Domain.{PortBerths, State, Trade}
  alias TijaraTides.Domain.Services.TradeSettlement

  defdelegate enqueue(state, id), to: ShipWorld, as: :request_berth

  def submit(state, account, trade, catalogue) do
    ship = State.get(state, "ships", trade.ship_id)

    if ship && ship["pending_side"] do
      {:error, :berth_order_pending}
    else
      case TradeSettlement.execute(state, account, trade, catalogue, :manual) do
        {:error, :berth_busy} ->
          next = ShipWorld.queue_trade(state, trade)

          {:ok, next, %{"queued" => true}}

        result ->
          result
      end
    end
  end

  def cancel(state, account, id) do
    company = account["company_id"]

    case State.get(state, "ships", id) do
      # Only a queued trade is cancellable. Without the pending check this would also
      # revoke a berth the ship currently holds, handing it to the next ship in line.
      %{"company_id" => ^company, "pending_side" => side} when not is_nil(side) ->
        {:ok, ShipWorld.cancel_pending_trade(state, id), %{}}

      _ ->
        {:error, :invalid_trade}
    end
  end

  def advance(state, catalogue) do
    state = ShipWorld.prepare_visits(state, catalogue)

    # Release completed visits before admitting the queue, but retain grants for
    # ships whose remaining orders will be executed later in this tick.
    state =
      Enum.reduce(State.entities(state, "ships"), state, fn {id, ship}, acc ->
        if ship["status"] == "docked" and not is_nil(ship["berth_granted_ms"]) and
             not has_work?(acc, ship) do
          ShipWorld.release_berth(acc, id)
        else
          acc
        end
      end)

    # Viability turns on funds, bankruptcy, orders and markets. None of the berth
    # transitions below touch any of those, so decide once and reuse the answer across
    # all three passes. Only docked ships with tickets or pending trades are candidates;
    # sailing, handling and idle ships must not incur speculative settlement checks.
    eligible =
      State.entities(state, "ships")
      |> Enum.filter(fn {_, ship} ->
        ship["status"] == "docked" and
          (not is_nil(ship["pending_side"]) or not is_nil(ship["berth_queued_ms"]))
      end)
      |> Map.new(fn {id, ship} -> {id, viable?(state, ship, catalogue)} end)

    state =
      Enum.reduce(State.entities(state, "ships"), state, fn {id, ship}, acc ->
        if ship["pending_side"] && eligible[id] do
          # A validated pending manual trade need not wait for an obsolete retry timer.
          acc =
            if is_nil(ship["berth_granted_ms"]) and is_nil(ship["berth_queued_ms"]) and
                 (ship["berth_retry_ms"] || 0) > acc.clock_ms,
               do: ShipWorld.release_berth(acc, id),
               else: acc

          enqueue(acc, id)
        else
          acc
        end
      end)

    state =
      Enum.reduce(Map.keys(catalogue["ports"]) |> Enum.sort(), state, fn port, acc ->
        model = PortBerthsWorld.load(acc, port, catalogue)

        {_model, decisions} =
          PortBerths.allocate(model, fn ship ->
            cond do
              not has_work?(acc, ship) -> :release
              eligible[ship["id"]] -> :grant
              true -> :retry
            end
          end)

        Enum.reduce(decisions, acc, fn {id, decision}, next ->
          case decision do
            :grant ->
              ShipWorld.grant_berth(next, id)

            :release ->
              ShipWorld.release_berth(next, id)

            :retry ->
              ShipWorld.release_berth(
                next,
                id,
                next.clock_ms + (catalogue["berth_retry_ms"] || 300_000)
              )
          end
        end)
      end)

    Enum.reduce(State.entities(state, "ships"), state, fn {id, ship}, acc ->
      # A grant can outlive the tick that issued it when the ship is mid-handling, so
      # the eligibility decided above still gates execution: the company may have gone
      # bankrupt or vanished since the grant was issued.
      if ship["pending_side"] && ship["berth_granted_ms"] && eligible[id] do
        company = State.get(acc, "companies", ship["company_id"])
        account = State.get(acc, "accounts", company["account_id"])

        trade = %Trade{
          ship_id: id,
          side: ship["pending_side"],
          good: ship["pending_good"],
          quantity: ship["pending_quantity"],
          limit: ship["pending_limit"],
          destination: ship["pending_destination"]
        }

        case TradeSettlement.execute(acc, account, trade, catalogue, :manual) do
          {:ok, next, _} -> ShipWorld.complete_pending_trade(next, id)
          {:error, _} -> acc
        end
      else
        acc
      end
    end)
  end

  # One definition of "still has something to do here", so a change to which statuses
  # count cannot drift between admission, viability and release.
  defp port_orders(state, ship) do
    State.entities(state, "ship_instructions")
    |> Map.values()
    |> Enum.filter(
      &(&1["ship_id"] == ship["id"] and &1["port"] == ship["port"] and
          &1["status"] in ["planned", "waiting"])
    )
  end

  defp has_work?(state, ship),
    do: not is_nil(ship["pending_side"]) or port_orders(state, ship) != []

  def pending_status(state, account, ship, catalogue) do
    trade = %Trade{
      ship_id: ship["id"],
      side: ship["pending_side"],
      good: ship["pending_good"],
      quantity: ship["pending_quantity"],
      limit: ship["pending_limit"],
      destination: ship["pending_destination"]
    }

    case TradeSettlement.validate(state, account, trade, catalogue) do
      :ok ->
        :berth_wait

      {:error, :insufficient_demand} ->
        q =
          TijaraTides.Domain.PortCargoMarketWorld.quote(
            state,
            catalogue,
            ship["port"],
            trade.good
          )

        if q["demand"] >= trade.quantity and q["buyer_budget"] < q["bid"] * trade.quantity,
          do: :buyer_budget,
          else: :insufficient_demand

      {:error, reason} ->
        reason
    end
  end

  defp viable?(state, ship, catalogue) do
    company = State.get(state, "companies", ship["company_id"])
    account = company && State.get(state, "accounts", company["account_id"])

    orders = port_orders(state, ship)

    trades =
      if ship["pending_side"] do
        [
          %Trade{
            ship_id: ship["id"],
            side: ship["pending_side"],
            good: ship["pending_good"],
            quantity: ship["pending_quantity"],
            limit: ship["pending_limit"],
            destination: ship["pending_destination"]
          }
        ]
      else
        Enum.map(
          orders,
          &%Trade{
            ship_id: ship["id"],
            side: &1["side"],
            good: &1["good"],
            quantity: 1,
            limit: &1["limit"],
            destination: &1["onward"]
          }
        )
      end

    account && is_nil(company["bankruptcy_ms"]) &&
      (trades == [] ||
         Enum.any?(
           trades,
           &(TradeSettlement.validate(state, account, &1, catalogue) == :ok)
         ))
  end

  def release_idle(state, catalogue) do
    Enum.reduce(State.entities(state, "ships"), state, fn {id, ship}, acc ->
      if ship["status"] == "docked" and not is_nil(ship["berth_granted_ms"]) do
        waiting = has_work?(acc, ship)

        retry = if waiting, do: acc.clock_ms + (catalogue["berth_retry_ms"] || 300_000), else: nil

        ShipWorld.release_berth(acc, id, retry)
      else
        acc
      end
    end)
  end
end
