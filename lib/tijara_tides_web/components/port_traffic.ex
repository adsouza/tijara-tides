defmodule TijaraTidesWeb.PortTraffic do
  @moduledoc "Port traffic rendered exclusively from the public ship projection."
  use TijaraTidesWeb, :html

  attr :public, :map, required: true
  attr :port, :string, required: true
  attr :grouping, :string, default: "status"

  def traffic(assigns) do
    ships =
      assigns.public["ships"]
      |> Map.values()
      |> Enum.filter(&(&1["port"] == assigns.port and &1["status"] != "sailing"))

    groups =
      Enum.group_by(ships, fn ship ->
        if assigns.grouping == "company", do: ship["company_id"], else: status(ship["status"])
      end)
      |> Enum.map(fn {key, ships} ->
        label = if assigns.grouping == "company", do: company(assigns.public, key), else: key
        %{key: key, label: label, ships: Enum.sort_by(ships, &{&1["name"], &1["id"]})}
      end)
      |> Enum.sort_by(&{&1.label, &1.key})

    assigns = assign(assigns, total: length(ships), groups: groups)

    ~H"""
    <section id="port-traffic" class="my-5 rounded-lg border border-slate-700 p-4">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <h3 class="text-lg font-semibold">Port traffic · {ship_count(@total)}</h3>
        <form id="traffic-grouping" phx-change="traffic-grouping">
          <label class="text-sm text-slate-300">
            Group by
            <select
              name="grouping"
              aria-label="Group port traffic"
              class="ml-2 rounded bg-slate-800 px-3 py-2"
            >
              <option value="status" selected={@grouping == "status"}>Status</option>
              <option value="company" selected={@grouping == "company"}>Company</option>
            </select>
          </label>
        </form>
      </div>
      <p class="mt-2 text-sm text-slate-400">
        Ships currently at {@port}; vessels at sea are excluded.
      </p>
      <p :if={@total == 0} class="mt-3 text-slate-300">No ships at this port.</p>
      <details
        :for={group <- @groups}
        id={group_id(@port, @grouping, group.key)}
        phx-mounted={JS.ignore_attributes("open")}
        class="mt-3 rounded border border-slate-700 px-3 py-2"
      >
        <summary class="cursor-pointer">{group.label} · {ship_count(length(group.ships))}</summary>
        <ul class="mt-2 space-y-2 text-sm">
          <li :for={ship <- group.ships}>
            <button
              phx-click="inspect-ship"
              phx-value-id={ship["id"]}
              class="text-teal-200 underline underline-offset-2"
            >{ship["name"]}</button>
            <span class="text-slate-400"> · {if @grouping == "company",
              do: status(ship["status"]),
              else: company(@public, ship["company_id"])}</span>
          </li>
        </ul>
      </details>
    </section>
    """
  end

  # Keep browser-owned expansion state while counts and ship lists update.
  # Port and grouping are part of the identity so unrelated groups cannot inherit it.
  defp group_id(port, grouping, key),
    do:
      "port-traffic-group-" <>
        Base.url_encode64(Jason.encode!([port, grouping, key]), padding: false)

  defp ship_count(1), do: "1 ship"
  defp ship_count(count), do: "#{count} ships"

  defp company(public, id), do: get_in(public, ["companies", id, "name"]) || "Unknown company"
  defp status("docked"), do: "Berthed"
  defp status("anchored"), do: "At anchorage"
  defp status(status), do: status |> String.replace("_", " ") |> String.capitalize()
end
