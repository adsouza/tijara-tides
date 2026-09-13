defmodule TijaraTides.Domain.Services.BerthAllocation do
  @moduledoc "Coordinate persisted ship queue tickets, admission, and delayed manual trades."
  alias TijaraTides.Domain.{PortBerths, Ship, State, Trade}
  alias TijaraTides.Domain.Services.TradeSettlement

  @clear %{
    pending_side: nil,
    pending_good: nil,
    pending_quantity: nil,
    pending_limit: nil,
    pending_destination: nil
  }

  def enqueue(state, id) do
    ship = State.get(state, "ships", id)

    if ship["status"] == "docked" and is_nil(ship["berth_queued_ms"]) and
         is_nil(ship["berth_granted_ms"]) and (ship["berth_retry_ms"] || 0) <= state.clock_ms,
       do: Ship.update_berth(state, id, %{berth_queued_ms: state.clock_ms}),
       else: state
  end

  def submit(state, account, trade, catalogue) do
    ship = State.get(state, "ships", trade.ship_id)

    if ship && ship["pending_side"] do
      {:error, :berth_order_pending}
    else
      case TradeSettlement.execute(state, account, trade, catalogue) do
        {:error, :berth_busy} ->
          next =
            Ship.update_berth(state, trade.ship_id, %{
              pending_side: trade.side,
              pending_good: trade.good,
              pending_quantity: trade.quantity,
              pending_limit: trade.limit,
              pending_destination: trade.destination
            })
            |> enqueue(trade.ship_id)

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
        {:ok,
         Ship.update_berth(
           state,
           id,
           Map.merge(@clear, %{berth_queued_ms: nil, berth_granted_ms: nil})
         ), %{}}

      _ ->
        {:error, :invalid_trade}
    end
  end

  def advance(state, catalogue) do
    state = Ship.prepare_visits(state, catalogue)

    # Release completed visits before admitting the queue, but retain grants for
    # ships whose remaining orders will be executed later in this tick.
    state =
      Enum.reduce(State.entities(state, "ships"), state, fn {id, ship}, acc ->
        if ship["status"] == "docked" and not is_nil(ship["berth_granted_ms"]) and
             not has_work?(acc, ship) do
          Ship.update_berth(acc, id, %{berth_granted_ms: nil, berth_retry_ms: nil})
        else
          acc
        end
      end)

    state =
      Enum.reduce(State.entities(state, "ships"), state, fn {id, ship}, acc ->
        if ship["pending_side"] && viable?(acc, ship, catalogue), do: enqueue(acc, id), else: acc
      end)

    state =
      Enum.reduce(Map.keys(catalogue["ports"]) |> Enum.sort(), state, fn port, acc ->
        capacity = PortBerths.capacity(catalogue, port)
        # Occupancy only rises, by one berth per grant, so carry the count through the
        # queue instead of rescanning every ship in the world for each candidate.
        occupied = Enum.count(PortBerths.ships(acc, port), &PortBerths.occupied?/1)

        PortBerths.queue(acc, port)
        |> Enum.reduce({acc, occupied}, fn ship, {acc, occupied} ->
          if occupied < capacity do
            cond do
              not has_work?(acc, ship) ->
                {Ship.update_berth(acc, ship["id"], %{
                   berth_queued_ms: nil,
                   berth_granted_ms: nil
                 }), occupied}

              viable?(acc, ship, catalogue) ->
                {Ship.update_berth(acc, ship["id"], %{
                   berth_queued_ms: nil,
                   berth_granted_ms: acc.clock_ms
                 }), occupied + 1}

              true ->
                {Ship.update_berth(acc, ship["id"], %{
                   berth_queued_ms: nil,
                   berth_retry_ms: acc.clock_ms + (catalogue["berth_retry_ms"] || 300_000)
                 }), occupied}
            end
          else
            {acc, occupied}
          end
        end)
        |> elem(0)
      end)

    Enum.reduce(State.entities(state, "ships"), state, fn {id, ship}, acc ->
      # A grant can outlive the tick that issued it when the ship is mid-handling, so
      # re-test viability here: the company may have gone bankrupt or vanished since.
      if ship["pending_side"] && ship["berth_granted_ms"] && viable?(acc, ship, catalogue) do
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

        case TradeSettlement.execute(acc, account, trade, catalogue) do
          {:ok, next, _} -> Ship.update_berth(next, id, @clear)
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
           &match?({:ok, _, _}, TradeSettlement.check(state, account, &1, catalogue))
         ))
  end

  def release_idle(state, catalogue) do
    Enum.reduce(State.entities(state, "ships"), state, fn {id, ship}, acc ->
      if ship["status"] == "docked" and not is_nil(ship["berth_granted_ms"]) do
        waiting = has_work?(acc, ship)

        retry = if waiting, do: acc.clock_ms + (catalogue["berth_retry_ms"] || 300_000), else: nil

        Ship.update_berth(acc, id, %{
          berth_granted_ms: nil,
          berth_retry_ms: retry
        })
      else
        acc
      end
    end)
  end
end
