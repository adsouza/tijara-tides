defmodule TijaraTidesWeb.GameUI.WarehousePanel do
  @moduledoc "Private storage and manual cargo transfers at the inspected port."
  use TijaraTidesWeb, :html
  import TijaraTidesWeb.GameUI.Presentation
  alias TijaraTides.UseCases.GameQueries
  attr :definitions, :any, required: true
  attr :view, :any, required: true
  attr :port, :string, required: true
  attr :ship, :any, required: true
  attr :draft, :map, required: true
  attr :request_id, :string, required: true

  def panel(assigns) do
    assigns =
      assign(
        assigns,
        :storage,
        GameQueries.warehouse_options(
          assigns.definitions,
          assigns.view,
          assigns.port,
          assigns.draft,
          assigns.ship
        )
      )

    ~H"""
    <details
      :if={@view.private && @view.private["company"]}
      id="warehouse-panel"
      phx-mounted={JS.ignore_attributes("open")}
      class="my-3 rounded border border-slate-700 p-2 text-sm"
    >
      <summary class="cursor-pointer font-semibold">{gettext("Warehouses")}</summary>
      <form
        id="warehouse-lease-form"
        phx-change="warehouse-draft"
        phx-submit="warehouse"
        class="flex flex-wrap items-end gap-2"
      >
        <input type="hidden" name="action" value="warehouse_lease" />
        <input type="hidden" name="request_id" value={@request_id} />
        <input type="hidden" name="port" value={@port} />
        <input type="hidden" name="storage" value={@storage.storage} />
        <input type="hidden" name="price" value={@storage.price} />
        <label>{gettext("Storage for cargo")}
        <select name="good" class="block max-w-40 rounded bg-slate-800 p-1">
          <option
            :for={{id, _} <- Enum.sort(@definitions.catalogue["goods"])}
            value={id}
            selected={id == @storage.good}
          >
            {cargo_name(id)}
          </option>
        </select></label>
        <label>{gettext("Blocks")}<input
          name="blocks"
          type="number"
          min="1"
          max={@storage.pool && @storage.pool.blocks - @storage.used}
          value={@storage.blocks}
          class="block w-16 rounded bg-slate-800 p-1"
        /></label>
        <label>{gettext("Active-world days")}<select
          name="days"
          class="block rounded bg-slate-800 p-1"
        ><option :for={n <- @storage.terms} value={n} selected={n == @storage.days}>
          {display_number(n)}
        </option></select></label>
        <button
          disabled={is_nil(@storage.price) or @storage.price > @storage.cash}
          class="rounded bg-teal-700 px-2 py-1 disabled:opacity-40"
        >{gettext("Lease")} {if @storage.price, do: money(@storage.price), else: "—"}</button>
      </form>
      <p :if={@storage.pool} class="my-2 text-xs text-slate-400">
        {gettext("%{free} of %{total} blocks available in this storage pool.",
          free: display_number(@storage.pool.blocks - @storage.used),
          total: display_number(@storage.pool.blocks)
        )}
      </p>
      <section
        :for={lease <- @storage.leases}
        id={"warehouse-#{lease.row["id"]}"}
        class="my-2 border-t border-slate-700 pt-2"
      >
        <p>
          {storage_name(lease.row["storage"])} {if lease.row["good"],
            do: "· " <> cargo_name(lease.row["good"])} · {gettext("%{used} / %{total} m³",
            used: display_number(div(lease.volume, 1000)),
            total: display_number(lease.row["blocks"] * 100)
          )}
        </p>
        <p class="text-xs text-slate-400">
          {if lease.row["expires_ms"] > @view.public["clock_ms"],
            do:
              gettext("Lease expires in %{minutes} mins",
                minutes:
                  display_number(div(lease.row["expires_ms"] - @view.public["clock_ms"], 60_000))
              ),
            else: gettext("Expired: collection only during the 12-hour grace period.")}
        </p>
        <table :if={lease.row["cargo"] != []} class="my-2 w-full text-start text-xs">
          <thead>
            <tr>
              <th class="text-start">{gettext("Cargo")}</th><th>{gettext("Lots")}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{good, batches} <- Enum.group_by(lease.row["cargo"], & &1["good"])}>
              <td>{cargo_name(good)}</td><td class="text-center">
                {display_number(Enum.sum(for b <- batches, do: b["quantity"]))}
              </td>
            </tr>
          </tbody>
        </table>
        <div :for={t <- lease.transfers} class="my-2 flex flex-wrap items-center gap-2">
          <span>{cargo_name(t.good)}</span>
          <form
            :for={{side, max} <- [{"store", t.store}, {"collect", t.collect}]}
            :if={max > 0}
            phx-submit="warehouse"
            class="flex gap-1"
          >
            <input type="hidden" name="action" value="warehouse_transfer" />
            <input type="hidden" name="warehouse" value={lease.row["id"]} />
            <input type="hidden" name="ship" value={@ship["id"]} />
            <input type="hidden" name="good" value={t.good} />
            <input type="hidden" name="side" value={side} />
            <input type="hidden" name="request_id" value={@request_id} />
            <input
              type="number"
              name="quantity"
              aria-label={gettext("Lots")}
              min="1"
              max={max}
              value={max}
              class="w-16 rounded bg-slate-800 p-1"
            />
            <button class="rounded border border-teal-700 px-2 py-1">{if side == "store",
              do: gettext("Store"),
              else: gettext("Collect")}</button>
          </form>
        </div>
        <form :if={lease.free_blocks > 0} phx-submit="warehouse" class="mt-2 flex items-center gap-2">
          <input type="hidden" name="action" value="warehouse_release" />
          <input type="hidden" name="warehouse" value={lease.row["id"]} />
          <input type="hidden" name="request_id" value={@request_id} />
          <input
            name="blocks"
            type="number"
            aria-label={gettext("Blocks to release")}
            min="1"
            max={lease.free_blocks}
            value={lease.free_blocks}
            class="w-16 rounded bg-slate-800 p-1"
          />
          <button class="rounded border border-slate-500 px-2 py-1">{gettext("Release space")}</button>
        </form>
      </section>
      <details
        id="warehouse-terms"
        phx-mounted={JS.ignore_attributes("open")}
        class="mt-2 text-xs text-slate-400"
      >
        <summary class="cursor-pointer">{gettext("Storage terms")}</summary>
        <p class="my-2 text-xs text-slate-400">
          {gettext(
            "Lease 100 m³ blocks. Rent is paid upfront and expensed over the term. Cargo keeps its cost and expiry. Transfers require an available berth and incur handling fees."
          )}
        </p>
        <p class="mt-1">
          {gettext(
            "Releasing empty capacity refunds half its unused rent. After expiry, collect cargo within 12 active-world hours. Remaining goods are cleared at half reference value and never for more than they cost; grace rent is capped at proceeds. Perishables continue aging. Liquid storage is dedicated to one cargo type."
          )}
        </p>
      </details>
    </details>
    """
  end

  defp storage_name("dry"), do: gettext("Ordinary storage")
  defp storage_name("reefer"), do: gettext("Refrigerated storage")
  defp storage_name("liquid"), do: gettext("Liquid storage")
end
