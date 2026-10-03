defmodule TijaraTides.UseCases.CommandPayload do
  @moduledoc "Admission schema for command fields; domain operations validate their values."

  @fields %{
    "locale" => ~w(locale),
    "auction_consign" => ~w(warehouse good quantity price),
    "auction_revise" => ~w(auction quantity price),
    "auction_withdraw" => ~w(auction),
    "auction_bid" => ~w(auction warehouse price),
    "auction_withdraw_bid" => ~w(auction),
    "markdown_preset_save" => ~w(preset name markdowns price_floor),
    "markdown_preset_delete" => ~w(preset),
    "exchange_place" =>
      ~w(warehouse good side quantity price expires_ms min_grade min_remaining_ms markdowns price_floor preset rebase),
    "exchange_amend" =>
      ~w(order quantity price expires_ms min_grade min_remaining_ms markdowns price_floor preset rebase),
    "exchange_cancel" => ~w(order),
    "plan_destination" => ~w(ship destination),
    "reroute" => ~w(ship destination fuel_limit),
    "warehouse_reserve" => ~w(warehouse ship good quantity kind stop_id),
    "warehouse_cancel_reservation" => ~w(reservation),
    "warehouse_replace" => ~w(warehouse days price),
    "warehouse_extend" => ~w(warehouse days price),
    "warehouse_renew" => ~w(warehouse days price),
    "warehouse_auto_renew" => ~w(warehouse days price),
    "warehouse_lease" => ~w(port storage good blocks days price),
    "warehouse_release" => ~w(warehouse blocks),
    "warehouse_transfer" => ~w(warehouse ship good quantity side min_remaining_ms),
    "cancel_berth_trade" => ~w(ship),
    "funding_policy" => ~w(policy),
    "visit_budget" => ~w(ship amount stop port),
    "guarantee" => ~w(account amount),
    "sell_ship" => ~w(ship minimum),
    "borrow" => ~w(amount),
    "repay" => ~w(loan),
    "recast" => ~w(loan amount),
    "bankruptcy" => [],
    "instruction_onward" => ~w(ship port onward auto_depart),
    "instruction" =>
      ~w(ship port side good quantity limit budget onward expires_in_ms min_remaining_ms preset markdowns price_floor),
    "cancel_instruction" => ~w(instruction),
    "company" => ~w(name),
    "purchase_ship" => ~w(class port price_limit name),
    "rename_ship" => ~w(ship name),
    "invite" => [],
    "buy" => ~w(ship good quantity limit destination),
    "sell" => ~w(ship good quantity limit destination),
    "sail" => ~w(ship destination fuel_limit)
  }
  @route_fields %{
    "add_stop" => ~w(port),
    "add_rule" =>
      ~w(stop side good quantity limit quantity_mode budget linked_warehouse_id min_remaining_ms),
    "update_rule" =>
      ~w(stop rule side good quantity limit quantity_mode budget linked_warehouse_id min_remaining_ms),
    "set_wait" => ~w(stop max_wait_ms),
    "remove_rule" => ~w(rule),
    "remove_stop" => ~w(stop),
    "start" => ~w(auto_depart),
    "resume" => ~w(auto_depart),
    "pause" => [],
    "stop_after" => [],
    "delete" => []
  }

  def actions, do: MapSet.new(["route" | Map.keys(@fields)])
  def route_operations, do: MapSet.new(Map.keys(@route_fields))

  @doc "Fields admitted for the payload's action and route operation, or nil when unsupported."
  def admitted(payload) when is_map(payload), do: fields(payload)
  def admitted(_), do: nil

  @doc "Keeps only admitted fields; an unsupported payload passes unchanged so admission rejects it."
  def select(payload) do
    case admitted(payload) do
      nil -> payload
      fields -> Map.take(payload, fields)
    end
  end

  def validate(payload) when is_map(payload) do
    fields = fields(payload)
    # Retain the envelope limit, allowing every documented optional field together.
    limit = max(12, if(fields, do: length(fields), else: 0))

    cond do
      map_size(payload) > limit -> {:error, :too_many_command_fields}
      byte_size(:erlang.term_to_binary(payload)) > 4096 -> {:error, :command_payload_too_large}
      is_nil(fields) -> {:error, :unsupported_command}
      Enum.any?(Map.keys(payload), &(&1 not in fields)) -> {:error, :unknown_command_fields}
      true -> :ok
    end
  end

  def validate(_), do: {:error, :invalid_command_payload}

  defp fields(%{"action" => "route"} = payload) do
    case @route_fields[payload["operation"]] do
      nil -> nil
      fields -> ~w(action ship operation) ++ fields
    end
  end

  defp fields(payload) do
    case @fields[payload["action"]] do
      nil -> nil
      fields -> ["action" | fields]
    end
  end
end
