defmodule TijaraTides.Domain.Manufacturing do
  @moduledoc "Finite recipes and atomic production plans over typed local inventories."
  alias TijaraTides.Domain.PortCargoMarket

  def recipes(catalogue), do: Map.get(catalogue, "manufacturing", %{})

  def inputs_at(catalogue, port) do
    roles = catalogue["ports"][port]["roles"]

    for {good, recipe} <- recipes(catalogue),
        role = roles[good] || "",
        String.contains?(role, "exp") and not String.contains?(role, "/"),
        input <- Map.keys(recipe["inputs"]),
        into: MapSet.new(),
        do: input
  end

  def validate!(catalogue) do
    Enum.each(recipes(catalogue), fn {output, r} ->
      unless is_map(catalogue["goods"][output]) and output not in PortCargoMarket.raw_goods() and
               is_map(r["inputs"]) and map_size(r["inputs"]) > 0 and
               is_integer(r["local_cost_cents"]) and r["local_cost_cents"] > 0,
             do: raise(ArgumentError, "Invalid manufacturing recipe")

      Enum.each(r["inputs"], fn {good, n} ->
        unless is_map(catalogue["goods"][good]) and catalogue["goods"][good]["shelf_ms"] == 0 and
                 good != output and is_integer(n) and n > 0,
               do: raise(ArgumentError, "Invalid manufacturing input")
      end)
    end)
  end

  def produce(%PortCargoMarket{} = output, inputs, recipe, prices, cycles) do
    cost =
      recipe["local_cost_cents"] +
        Enum.sum(for {good, n} <- recipe["inputs"], do: n * Map.fetch!(prices, good))

    available =
      Enum.map(recipe["inputs"], fn {good, n} -> div(Map.fetch!(inputs, good).stock, n) end)

    count =
      Enum.min([max(0, cycles), max(0, 500 - output.stock), div(output.budget, cost) | available])

    if output.seller and not output.merchant and count > 0 do
      consumed =
        Map.new(recipe["inputs"], fn {good, n} ->
          input = Map.fetch!(inputs, good)

          {good,
           %{
             input
             | stock: input.stock - n * count,
               budget: input.budget + prices[good] * n * count
           }}
        end)

      {%{output | stock: output.stock + count, budget: output.budget - count * cost}, consumed}
    else
      {output, %{}}
    end
  end
end
