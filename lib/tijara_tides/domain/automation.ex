defmodule TijaraTides.Domain.Automation do
  @moduledoc "Pure departure policy and configurable active-world accumulation rules."
  @defaults %{"wait_ms" => 1_800_000, "window_ms" => 600_000, "cooldown_ms" => 1_800_000}
  def settings(catalogue) do
    Map.new(@defaults, fn {key, default} ->
      value = get_in(catalogue, ["departure_funding", key]) || default

      unless is_integer(value) and value > 0 and value <= 2_592_000_000,
        do: raise(ArgumentError, "Invalid departure funding timing")

      {key, value}
    end)
  end

  def requirement(fuel, budget, policy), do: fuel + if(policy == "wait", do: budget || 0, else: 0)
  def purchase_amount(nil, _policy, _available), do: nil
  def purchase_amount(_budget, "skip", _available), do: 0
  def purchase_amount(budget, "wait", _available), do: budget
  def purchase_amount(budget, "reduced", available), do: min(budget, max(0, available))
end
