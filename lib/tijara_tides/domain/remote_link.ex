defmodule TijaraTides.Domain.RemoteLink do
  @moduledoc "Pure remote link lifecycle and economic rules."
  @fields ~w(id company_id ship_id stop_id good warehouse_id port order_id generation filled status)a
  @enforce_keys @fields
  defstruct @fields

  def new(rule, order_id, generation, port),
    do: %__MODULE__{
      id: rule["id"],
      company_id: rule["company_id"],
      ship_id: rule["ship_id"],
      stop_id: rule["stop_id"],
      good: rule["good"],
      warehouse_id: rule["linked_warehouse_id"],
      port: port,
      order_id: order_id,
      generation: generation,
      filled: 0,
      status: "active"
    }

  def fill(%__MODULE__{} = link, quantity), do: %{link | filled: link.filled + quantity}
  def close(%__MODULE__{} = link, status), do: %{link | status: status}
end
