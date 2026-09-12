defmodule TijaraTidesWeb.PortTraffic do
  @moduledoc "Port traffic rendered exclusively from the public ship projection."
  use TijaraTidesWeb, :html

  attr :public, :map, required: true
  attr :classes, :map, default: %{}
  attr :port, :string, required: true
  attr :grouping, :string, default: "status"

  def traffic(assigns) do
    ships =
      assigns.public["ships"]
      |> Map.values()
      |> Enum.filter(&(&1["port"] == assigns.port and &1["status"] != "sailing"))

    groups =
      Enum.group_by(ships, fn ship ->
        case assigns.grouping do
          "company" -> ship["company_id"]
          "kind" -> ship["class"]
          _ -> status(ship["status"])
        end
      end)
      |> Enum.map(fn {key, ships} ->
        label =
          case assigns.grouping do
            "company" -> company(assigns.public, key)
            "kind" -> l10n(get_in(assigns.classes, [key, "name"]) || key || "Unknown kind")
            _ -> l10n(key)
          end

        %{key: key, label: label, ships: Enum.sort_by(ships, &{&1["name"], &1["id"]})}
      end)
      |> Enum.sort_by(&{&1.label, &1.key})

    assigns = assign(assigns, total: length(ships), groups: groups)

    ~H"""
    <section id="port-traffic" class="my-5 rounded-lg border border-slate-700 p-4">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <h3 class="text-lg font-semibold">
          {gettext("Port traffic · %{value1}", value1: ship_count(@total))}
        </h3>
        <form id="traffic-grouping" phx-change="traffic-grouping">
          <label class="text-sm text-slate-300">
            {gettext("Group by")}
            <select
              name="grouping"
              aria-label={gettext("Group port traffic")}
              class="ml-2 rounded bg-slate-800 px-3 py-2"
            >
              <option value="status" selected={@grouping == "status"}>{gettext("Status")}</option>
              <option value="company" selected={@grouping == "company"}>{gettext("Company")}</option>
              <option value="kind" selected={@grouping == "kind"}>{gettext("Kind")}</option>
            </select>
          </label>
        </form>
      </div>
      <p class="mt-2 text-sm text-slate-400">
        {gettext("Ships currently at %{value1}; vessels at sea are excluded.", value1: l10n(@port))}
      </p>
      <p :if={@total == 0} class="mt-3 text-slate-300">{gettext("No ships at this port.")}</p>
      <details
        :for={group <- @groups}
        id={group_id(@port, @grouping, group.key)}
        open={@grouping == "status" and group.key in ["Loading", "Unloading"]}
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
              do: l10n(status(ship["status"])),
              else: company(@public, ship["company_id"])}</span>
            <span :if={@grouping == "kind"} class="text-slate-400"> · {l10n(status(ship["status"]))}</span>
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

  defp ship_count(count), do: ngettext("%{count} ship", "%{count} ships", count)

  defp company(public, id),
    do: get_in(public, ["companies", id, "name"]) || gettext("Unknown company")

  defp status("docked"), do: "Berthed"
  defp status("anchored"), do: "At anchorage"
  defp status(status), do: status |> String.replace("_", " ") |> String.capitalize()
end
