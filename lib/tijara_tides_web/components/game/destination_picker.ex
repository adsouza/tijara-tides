defmodule TijaraTidesWeb.GameUI.DestinationPicker do
  use TijaraTidesWeb, :html
  alias TijaraTides.UseCases.GameQueries
  import TijaraTidesWeb.GameUI.Presentation, only: [cargo_roi: 1, money: 1]
  attr :definitions, :any, required: true
  attr :view, :any, required: true
  attr :ship, :map, required: true
  attr :destination, :any, default: nil

  def panel(assigns) do
    assigns =
      assign(
        assigns,
        :matrix,
        GameQueries.destination_matrix(assigns.definitions, assigns.view, assigns.ship)
      )

    scale =
      assigns.matrix.rows
      |> Enum.flat_map(fn row ->
        Enum.flat_map(Map.values(row.cells), &[&1.outbound, &1.inbound])
      end)
      |> Enum.filter(&(&1 && is_number(&1.roi) && &1.roi > 0))
      |> Enum.map(&abs(&1.roi))
      |> Enum.max(fn -> 1 end)

    assigns = assign(assigns, :roi_scale, max(scale, 0.0001))

    ~H"""
    <div id="destination-picker-backdrop" class="destination-picker-backdrop">
      <.focus_wrap id="destination-picker-focus">
        <section
          id="destination-picker"
          role="dialog"
          aria-modal="true"
          aria-labelledby="destination-picker-title"
          aria-describedby="destination-picker-help"
          class="destination-picker"
          phx-window-keydown="destination-picker-close"
          phx-key="Escape"
          phx-click-away="destination-picker-close"
          phx-mounted={JS.focus_first(to: "#destination-picker")}
          phx-remove={JS.focus(to: "#destination-picker-trigger")}
        >
          <div class="flex items-start justify-between gap-4">
            <h2 id="destination-picker-title" class="text-lg font-semibold">
              {gettext("Trade opportunities from %{port}", port: l10n(@ship["port"]))}
            </h2>
            <button
              type="button"
              phx-click="destination-picker-close"
              class="rounded border px-3 py-1"
            >{gettext("Close")}</button>
          </div>
          <p id="destination-picker-help" class="my-3 text-xs text-slate-400">
            {gettext(
              "Rows rank by estimated net profit on the next voyage, then distance. Tankers rank by combined profit including the best profitable loaded onward voyage. Suggested mixes share hold space and available cash, and include cargo aboard. Profit deducts recorded cargo cost, purchase and sale handling, fuel, canals, cleaning, crew costs for this ship. Maintenance and fleet upkeep are reserved for affordability but maintenance is excluded from profit. These are approximate suggestions, not orders or a guaranteed optimal mix. Prices, demand and buyer funds may change; berth delays, new cargo spoilage and queued orders are excluded. With a queued trade, estimates use only cargo already aboard. Return symbols do not affect ranking; tanker onward estimates may include a return or another destination. Symbols still show individual cargo ROI before voyage costs: squares for cargo aboard, circles for purchases, green outbound and red return. Skulls mean negative ROI; hollow symbols mean zero or unavailable ROI. Hover or focus for details."
            )}
          </p>
          <div class="mb-3 flex flex-wrap gap-4 text-sm">
            <span class="text-green-400">■ {gettext("Cargo aboard")}</span>
            <span class="text-green-400">● {gettext("Outbound")}</span>
            <span class="text-red-400">● {gettext("Return")}</span>
          </div>
          <div class="destination-matrix-scroll">
            <table class="destination-matrix text-sm">
              <thead>
                <tr>
                  <th scope="col" class="destination-port">{gettext("Port")}</th>
                  <th scope="col">{gettext("Estimated net profit")}</th>
                  <th scope="col">{gettext("Distance (nm)")}</th>
                  <th :for={{_, good} <- @matrix.goods} scope="col">{l10n(good["name"])}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @matrix.rows}>
                  <th scope="row" class="destination-port">
                    <button
                      type="button"
                      phx-click="preview"
                      phx-value-destination={row.port}
                      aria-pressed={to_string(row.port == @destination)}
                      class="rounded text-teal-200 underline underline-offset-2"
                    >
                      {l10n(row.port)}
                    </button>
                  </th>
                  <td class="tabular-nums text-left">
                    <%= if row.plan do %>
                      <strong>{money(row.best)}</strong>
                      <p :if={@ship["class"] == "tanker"} class="text-xs text-slate-400">
                        {if row.plan.onward,
                          do: gettext("Two voyages"),
                          else: gettext("No profitable onward load")}
                      </p>
                      <details
                        id={"destination-plan-" <> row.port}
                        phx-mounted={JS.ignore_attributes(["open"])}
                      >
                        <summary class="cursor-pointer text-xs">
                          {gettext("Suggested cargo mix")}
                        </summary>
                        <div class="min-w-48 text-xs">
                          <p>
                            {gettext("Next voyage profit: %{profit}", profit: money(row.plan.profit))}
                          </p>
                          <p>{gettext("Voyage costs: %{cost}", cost: money(row.plan.costs))}</p>
                          <p>{gettext("Purchases: %{cost}", cost: money(row.plan.spent))}</p>
                          <p :for={cargo <- row.plan.purchases}>
                            {gettext("Buy %{lots} lots of %{cargo}",
                              lots: display_number(cargo.lots),
                              cargo: l10n(@definitions.catalogue["goods"][cargo.good]["name"])
                            )}
                          </p>
                          <p :for={cargo <- row.plan.sales}>
                            {gettext("Sell %{lots} lots of %{cargo}",
                              lots: display_number(cargo.lots),
                              cargo: l10n(@definitions.catalogue["goods"][cargo.good]["name"])
                            )}
                          </p>
                          <%= if Map.get(row.plan, :onward) do %>
                            <p class="mt-2 font-semibold">
                              {gettext("Then sail to %{port}: %{profit}",
                                port: l10n(row.plan.onward.destination),
                                profit: money(row.plan.onward.profit)
                              )}
                            </p>
                            <p :for={cargo <- row.plan.onward.purchases}>
                              {gettext("Buy %{lots} lots of %{cargo}",
                                lots: display_number(cargo.lots),
                                cargo: l10n(@definitions.catalogue["goods"][cargo.good]["name"])
                              )}
                            </p>
                          <% end %>
                        </div>
                      </details>
                    <% else %>
                      <span class="text-xs">{gettext("Insufficient voyage funds")}</span>
                    <% end %>
                  </td>
                  <td class="tabular-nums">{display_number(row.distance)}</td>
                  <td :for={{id, _} <- @matrix.goods} class="opportunity-cell">
                    <%= for {direction, opportunity} <- [{:outbound, row.cells[id].outbound}, {:inbound, row.cells[id].inbound}], opportunity do %>
                      <% description =
                        if Map.get(opportunity, :source) == :aboard do
                          gettext(
                            "Sell aboard cargo: %{roi} · %{lots} lots · %{proceeds} after sale handling",
                            roi:
                              if(is_number(opportunity.roi),
                                do: cargo_roi(opportunity.roi) <> " ROI",
                                else: gettext("ROI unavailable for zero-cost cargo")
                              ),
                            lots: display_number(opportunity.lots),
                            proceeds: money(opportunity.proceeds)
                          )
                        else
                          gettext("%{direction}: %{roi} ROI · %{lots} market lots",
                            direction:
                              if(direction == :outbound,
                                do: gettext("Outbound"),
                                else: gettext("Return")
                              ),
                            roi: cargo_roi(opportunity.roi),
                            lots: display_number(opportunity.lots)
                          )
                        end %>
                      <span
                        class={[
                          "opportunity-disc",
                          if(direction == :outbound, do: "outbound", else: "inbound")
                        ]}
                        tabindex="0"
                        role="img"
                        aria-label={description}
                      >
                        <svg
                          :if={is_nil(opportunity.roi) || opportunity.roi >= 0}
                          width="48"
                          height="48"
                          viewBox="0 0 48 48"
                          aria-hidden="true"
                        >
                          <rect
                            :if={Map.get(opportunity, :source) == :aboard}
                            x={24 - max(2, 21 * abs(opportunity.roi || 0) / @roi_scale)}
                            y={24 - max(2, 21 * abs(opportunity.roi || 0) / @roi_scale)}
                            width={2 * max(2, 21 * abs(opportunity.roi || 0) / @roi_scale)}
                            height={2 * max(2, 21 * abs(opportunity.roi || 0) / @roi_scale)}
                            fill={
                              if is_number(opportunity.roi) && opportunity.roi > 0,
                                do: "currentColor",
                                else: "none"
                            }
                            stroke="currentColor"
                            stroke-width="2"
                          />
                          <circle
                            :if={Map.get(opportunity, :source) != :aboard}
                            cx="24"
                            cy="24"
                            r={max(2, 21 * abs(opportunity.roi || 0) / @roi_scale)}
                            fill={
                              if is_number(opportunity.roi) && opportunity.roi > 0,
                                do: "currentColor",
                                else: "none"
                            }
                            stroke="currentColor"
                            stroke-width="2"
                          />
                        </svg>
                        <span
                          :if={is_number(opportunity.roi) && opportunity.roi < 0}
                          class="opportunity-skull"
                          aria-hidden="true"
                        >☠︎</span>
                        <span class="opportunity-tooltip" aria-hidden="true">{description}</span>
                      </span>
                    <% end %>
                    <span
                      :if={!row.cells[id].outbound && !row.cells[id].inbound}
                      aria-label={gettext("No trade opportunity")}
                    >—</span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p :if={@matrix.goods == []} class="mt-3 text-sm text-slate-400">
            {gettext("No compatible trade opportunities right now. You can still choose a port.")}
          </p>
        </section>
      </.focus_wrap>
    </div>
    """
  end
end
