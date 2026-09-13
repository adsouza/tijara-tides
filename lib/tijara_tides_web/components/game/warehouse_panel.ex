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
        <input type="hidden" name="price" value={@storage.price} />
        <label class="min-w-0 w-full">
          {gettext("Warehouse type")}
          <select name="storage" class="block w-full rounded bg-slate-800 p-1">
            <option
              :for={kind <- ["dry", "reefer", "liquid"]}
              value={kind}
              selected={kind == @storage.storage}
            >
              {storage_name(kind)} — {if kind == "dry",
                do: gettext("non-perishable solid goods"),
                else:
                  Enum.map_join(@storage.storage_goods[kind] || [], ", ", fn {id, _} ->
                    cargo_name(id)
                  end)}
            </option>
          </select>
        </label>
        <p class="w-full text-xs text-slate-400">
          {if @storage.storage == "liquid",
            do: gettext("Liquid storage is dedicated to one selected cargo per lease."),
            else: gettext("This warehouse can store any combination of the listed cargo types.")}
        </p>
        <label :if={@storage.storage == "liquid"}>
          {gettext("Cargo")}
          <select name="good" class="block rounded bg-slate-800 p-1">
            <option
              :for={{id, _} <- @storage.storage_goods["liquid"]}
              value={id}
              selected={id == @storage.good}
            >
              {cargo_name(id)}
            </option>
          </select>
        </label>
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
          {warehouse_name(lease.row)} · {gettext("%{used} / %{total} m³",
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
        <p :if={lease.reserved_volume > 0} class="text-xs text-slate-400">
          {gettext("Reserved receiving space: %{volume} m³",
            volume: display_number(div(lease.reserved_volume, 1000))
          )}
        </p>
        <p :if={lease.row["next_days"]} class="text-xs text-teal-300">
          {gettext("Next term paid: %{days} days, starting at current expiry.",
            days: display_number(lease.row["next_days"])
          )}
        </p>
        <details
          id={"warehouse-renewal-#{lease.row["id"]}"}
          phx-mounted={JS.ignore_attributes("open")}
          class="my-2"
        >
          <summary class="cursor-pointer font-semibold">{gettext("Lease renewal")}</summary>
          <p class="my-1 text-xs text-slate-400">
            {gettext(
              "Renew during the final 6 hours. The daily quote locks when the window opens; the paid term starts at expiry. Auto-renew retries while funds are available and the locked daily rent is within your cap."
            )}
          </p>
          <p :if={!lease.renewal_open && !lease.row["next_days"]} class="text-xs text-slate-400">
            {gettext("The renewal window is closed.")}
          </p>
          <div :if={lease.renewal_open && lease.renewal_rate} class="flex flex-wrap gap-2">
            <form :for={days <- @storage.terms} phx-submit="warehouse">
              <input type="hidden" name="action" value="warehouse_renew" />
              <input type="hidden" name="warehouse" value={lease.row["id"]} />
              <input type="hidden" name="request_id" value={@request_id} />
              <input type="hidden" name="days" value={days} />
              <input type="hidden" name="price" value={lease.renewal_rate * days} />
              <button
                disabled={lease.renewal_rate * days > @storage.cash}
                class="rounded border border-teal-700 px-2 py-1 disabled:opacity-40"
              >{gettext("Renew %{days} days · %{price}",
                days: display_number(days),
                price: money(lease.renewal_rate * days)
              )}</button>
            </form>
          </div>
          <form phx-submit="warehouse" class="mt-2 flex flex-wrap items-end gap-2">
            <input type="hidden" name="action" value="warehouse_auto_renew" />
            <input type="hidden" name="warehouse" value={lease.row["id"]} />
            <input type="hidden" name="request_id" value={@request_id} />
            <label>{gettext("Auto-renew term")}
            <select name="days" class="block rounded bg-slate-800 p-1">
              <option value="0" selected={is_nil(lease.row["auto_days"])}>{gettext("Off")}</option>
              <option
                :for={days <- @storage.terms}
                value={days}
                selected={lease.row["auto_days"] == days}
              >
                {gettext("%{days} days", days: display_number(days))}
              </option>
            </select></label>
            <label>{gettext("Daily rent cap")}<input
              type="number"
              name="daily_cap"
              min="0"
              value={div((lease.row["auto_cap"] || lease.renewal_rate || 0) + 99, 100)}
              class="block w-28 rounded bg-slate-800 p-1"
            /></label>
            <button class="rounded border border-teal-700 px-2 py-1">{gettext("Save renewal settings")}</button>
          </form>
        </details>
        <details
          id={"warehouse-reservations-#{lease.row["id"]}"}
          phx-mounted={JS.ignore_attributes("open")}
          class="my-2"
        >
          <summary class="cursor-pointer font-semibold">{gettext("Reservations")}</summary>
          <p class="my-1 text-xs text-slate-400">
            {gettext(
              "Earmark owned cargo or receiving space for the selected ship. Matching transfers use its reservation first. Linked reservations release when their route stop is removed. Unlinked reservations remain until used or cancelled."
            )}
          </p>
          <div :for={r <- lease.reservations} class="my-1 flex flex-wrap items-center gap-2">
            <span>{r.ship ||
              if(r.auction, do: gettext("Auction commitment"), else: gettext("Exchange order"))} · {cargo_name(
              r.good
            )} · {display_number(r.quantity)} · {if r.kind ==
                                                      "stock",
                                                    do: gettext("Owned stock"),
                                                    else: gettext("Receiving space")}</span>
            <form :if={r.ship != nil} phx-submit="warehouse">
              <input type="hidden" name="action" value="warehouse_cancel_reservation" />
              <input type="hidden" name="reservation" value={r.id} />
              <input type="hidden" name="request_id" value={@request_id} />
              <button class="rounded border border-slate-500 px-2 py-1">{gettext("Cancel reservation")}</button>
            </form>
          </div>
          <form
            :for={option <- lease.reservation_options}
            phx-submit="warehouse"
            class="my-1 flex flex-wrap items-center gap-2"
          >
            <input type="hidden" name="action" value="warehouse_reserve" />
            <input type="hidden" name="warehouse" value={lease.row["id"]} />
            <input type="hidden" name="request_id" value={@request_id} />
            <input type="hidden" name="ship" value={@ship["id"]} />
            <input type="hidden" name="good" value={option.good} />
            <input type="hidden" name="kind" value={option.kind} />
            <span>{cargo_name(option.good)} · {if option.kind == "stock",
              do: gettext("Owned stock"),
              else: gettext("Receiving space")}</span>
            <input
              type="number"
              name="quantity"
              min="1"
              max={option.max}
              value={option.max}
              aria-label={gettext("Lots")}
              class="w-16 rounded bg-slate-800 p-1"
            />
            <select
              :if={lease.collection_stops != []}
              name="stop_id"
              aria-label={gettext("Collection stop")}
              class="max-w-32 rounded bg-slate-800 p-1"
            >
              <option value="">{gettext("Unlinked")}</option>
              <option :for={stop <- lease.collection_stops} value={stop["id"]}>
                {gettext("Stop %{number}", number: display_number(stop["position"] + 1))}
              </option>
            </select>
            <button class="rounded border border-teal-700 px-2 py-1">{gettext("Reserve")}</button>
          </form>
        </details>
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
end
