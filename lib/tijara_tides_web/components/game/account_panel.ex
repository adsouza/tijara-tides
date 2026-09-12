defmodule TijaraTidesWeb.GameUI.AccountPanel do
  @moduledoc "AccountPanel rendering; events remain owned by GameLive."
  use TijaraTidesWeb, :html
  import TijaraTidesWeb.GameUI.Presentation

  attr :invite_code, :any, required: true
  attr :request_id, :any, required: true
  attr :view, :any, required: true

  def panel(assigns) do
    ~H"""
    <details
      :if={@view.private}
      id="company-menu"
      class="company-menu"
      phx-mounted={JS.ignore_attributes("open")}
    >
      <summary class="company-menu-trigger popup-menu-trigger" phx-click="report-close">
        <span>{gettext("Account, finance & invitations")}</span>
      </summary>
      <div class="company-menu-body">
        <div class="company-menu-dismiss">
          <h3
            :if={@view.private["account"]["email"]}
            id="verified-email"
            class="min-w-0 flex-1 break-words"
          >
            {gettext("Verified Email identity: %{value1}", value1: @view.private["account"]["email"])}
          </h3>
          <button
            type="button"
            phx-click={
              JS.remove_attribute("open", to: "#company-menu")
              |> JS.focus(to: "#company-menu > summary")
            }
            aria-label={gettext("Close account, finance and invitations")}
            class="shrink-0 rounded border border-slate-500 px-3 py-1"
          >{gettext("Close ✕")}</button>
        </div>
        <Layouts.language_selector />
        <p :if={is_nil(@view.private["account"]["email"])} class="text-sm text-amber-100">
          <%= if Application.get_env(:tijara_tides, :email_enabled, false) do %>
            {gettext(
              "Link an email to sign in on another device. Until an email is verified, keep this device session to retain access. Invitations cannot be reused to sign in."
            )}
          <% else %>
            {gettext(
              "Email linking is not available on this server yet. Keep this device session to retain access. Invitations cannot be reused to sign in."
            )}
          <% end %>
        </p>
        <section class="my-6 rounded-xl bg-slate-900 p-5">
          <section
            :if={
              Application.get_env(:tijara_tides, :email_enabled, false) and
                is_nil(@view.private["account"]["email"])
            }
            id="email-identity"
            class="my-4 space-y-2"
          >
            <h3 :if={is_nil(@view.private["account"]["email"])}>{gettext("Email identity")}</h3>
            <div :if={is_nil(@view.private["account"]["email"])} id="email-verification">
              <.form
                for={%{}}
                id="email-link-form"
                phx-submit="email-request"
                class="flex flex-wrap gap-2"
              >
                <input type="hidden" name="purpose" value="link" />
                <input
                  type="email"
                  name="email"
                  required
                  maxlength="254"
                  aria-label={gettext("Email to link")}
                  class="rounded bg-slate-800 p-2"
                />
                <div class="flex items-center gap-2">
                  <button class="shrink-0 rounded border p-2">{gettext("Send verification link")}</button>
                  <p class="text-sm">{gettext("Verify your email using the link we send.")}</p>
                </div>
              </.form>
              <p class="text-sm">
                {gettext("Addresses already linked to another account cannot be used.")}
              </p>
              <ul class="text-xs space-y-1">
                <li
                  :for={delivery <- @view.private["email_deliveries"] || []}
                  :if={delivery["purpose"] == "link"}
                >
                  {delivery["email"]}: {if delivery["verified"],
                    do: l10n("verified"),
                    else: l10n(delivery["delivery"])}
                </li>
              </ul>
            </div>
          </section>
          <section
            :if={@view.private["account"]["email"]}
            id="invitations"
            class="my-4 space-y-2"
          >
            <h2 class="text-xl">{gettext("Invitations")}</h2>
            <p :if={@view.private["account"]["invite_quota"] < 1}>
              {gettext("Available invitations: 0")}
            </p>
            <div
              :if={@view.private["account"]["invite_quota"] > 0}
              class="flex flex-wrap items-end gap-3"
            >
              <div class="min-w-0 flex-[1_1_16rem] space-y-1">
                <p>
                  {gettext("Available invitations: %{value1}",
                    value1: @view.private["account"]["invite_quota"]
                  )}
                </p>
                <.form
                  :if={Application.get_env(:tijara_tides, :email_enabled, false)}
                  for={%{}}
                  id="email-invite-form"
                  phx-submit="email-request"
                  class="flex flex-wrap gap-2"
                >
                  <input type="hidden" name="purpose" value="invite" />
                  <input
                    type="email"
                    name="email"
                    required
                    maxlength="254"
                    aria-label={gettext("Invitee email")}
                    placeholder={gettext("Invitee email")}
                    class="min-w-0 flex-1 rounded bg-slate-800 p-2"
                  />
                  <button
                    disabled={
                      @view.private["account"]["invite_quota"] < 1 or
                        not is_nil(@view.private["account"]["suspended_ms"])
                    }
                    class="rounded border p-2 disabled:opacity-40"
                  >{gettext("Send invitation")}</button>
                </.form>
              </div>
              <span
                :if={Application.get_env(:tijara_tides, :email_enabled, false)}
                class="py-2 text-slate-400"
              >{gettext("or")}</span>
              <button
                phx-click="invite"
                phx-value-request_id={@request_id}
                class="rounded border border-teal-700 px-4 py-2"
              >{gettext("Generate shareable")}<br />{gettext("invitation code")}</button>
            </div>
            <p :if={@invite_code} class="mt-3 break-all font-mono text-teal-200">
              {@invite_code}
            </p>
            <p
              :if={
                @view.private["account"]["invite_quota"] > 0 and
                  Application.get_env(:tijara_tides, :email_enabled, false)
              }
              class="text-sm"
            >
              {gettext(
                "Uses one invitation. The recipient verifies the email when redeeming the link. You will not receive their sign-in credential."
              )}
            </p>
            <ul class="text-xs space-y-1">
              <li
                :for={delivery <- @view.private["email_deliveries"] || []}
                :if={delivery["purpose"] == "invite"}
              >
                {delivery["email"]}: {if delivery["verified"],
                  do: l10n("verified"),
                  else: l10n(delivery["delivery"])}
                <span :if={delivery["purpose"] == "invite" and not delivery["verified"]}>
                  {gettext("· expires in %{value1}",
                    value1:
                      invitation_time_remaining(
                        max(0, delivery["expires_ms"] - @view.public["clock_ms"])
                      )
                  )}
                </span>
              </li>
            </ul>
          </section>
          <section
            :if={
              @view.private["guarantees"]["active"] != nil or
                @view.private["guarantees"]["pending"] != [] or
                Enum.any?(
                  @view.private["guarantees"]["pledges"],
                  &(&1["status"] == "pledged")
                )
            }
            id="sponsor-guarantees"
            class="my-4 space-y-3"
          >
            <h3 class="text-lg">{gettext("Sponsor guarantees")}</h3>
            <p :if={not @view.private["guarantees"]["eligible"]}>
              {gettext(
                "To sponsor a player, clear overdue bills and hold at least as much unreserved cash as your own outstanding loan principal and interest."
              )}
            </p>

            <p :if={@view.private["guarantees"]["active"]}>
              {gettext("Your borrowing is backed by a %{value1} sponsor pledge.",
                value1: money(@view.private["guarantees"]["active"]["amount"])
              )}
            </p>

            <div
              :for={g <- @view.private["guarantees"]["pledges"]}
              :if={g["status"] == "pledged"}
            >
              <p :if={is_nil(g["settlement"])}>
                {gettext(
                  "%{value1} locked as a guarantee. It is returned to the sponsoring company after the guaranteed loans are repaid; on bankruptcy, unpaid loan debt is covered up to this cap and the rest is refunded.",
                  value1: money(g["amount"])
                )}
              </p>
              <p :if={g["settlement"] == "release"} class="rounded border border-emerald-700 p-2">
                {gettext(
                  "The guaranteed loans are repaid. %{value1} returns to your company the next time it settles — within a few seconds, or on your next action.",
                  value1: money(g["amount"])
                )}
              </p>
              <p :if={g["settlement"] == "claim"} class="rounded border border-amber-700 p-2">
                {gettext(
                  "Your invitee has gone bankrupt. %{value1} of this %{value2} guarantee will be forfeited and %{value3} returned, the next time your company settles.",
                  value1: money(g["settlement_amount"]),
                  value2: money(g["amount"]),
                  value3: money(g["amount"] - g["settlement_amount"])
                )}
              </p>
            </div>
            <.form
              :for={candidate <- @view.private["guarantees"]["pending"]}
              :if={@view.private["company"] && is_nil(@view.private["account"]["suspended_ms"])}
              for={%{}}
              id={"guarantee-" <> candidate["id"]}
              phx-submit="guarantee"
              data-confirm={
                gettext(
                  "Fund this guarantee? Cash is locked immediately, including before the invitee borrows. It can be forfeited on their bankruptcy and is not withdrawable. Your own bankruptcy does not release it."
                )
              }
              class="space-y-2 rounded border p-3"
            >
              <p>
                {gettext("Guarantee %{value1}. The pledge caps their borrowing and your liability.",
                  value1: candidate["name"]
                )}
              </p>
              <input type="hidden" name="request_id" value={@request_id} />
              <input type="hidden" name="account" value={candidate["id"]} />
              <input
                type="number"
                name="amount"
                aria-label={gettext("Sponsor pledge in dollars")}
                min={div(candidate["minimum"], 100)}
                max={div(candidate["maximum"], 100)}
                value={div(candidate["minimum"], 100)}
                class="w-32 rounded bg-slate-800 p-2"
              />
              <button
                disabled={not candidate["enabled"]}
                phx-disable-with={gettext("Pledging…")}
                class="rounded border p-2"
              >{gettext("Pledge & reinstate")}</button>
            </.form>
          </section>
          <section
            :if={@view.private["company"]}
            id="company-finance"
            class="mt-4 space-y-3 border-t border-slate-600 pt-3"
          >
            <h3 class="text-lg">{gettext("Loans and repayments")}</h3>

            <p :if={@view.private["finance"]["requires_guarantee"]}>
              {gettext(
                "New borrowing requires your original sponsor's cash pledge, even after earlier guaranteed loans were repaid."
              )}
            </p>
            <p>
              {gettext(
                "Debt: %{value1} · Available credit: %{value2} · Lifetime bankruptcies: %{value3}",
                value1: money(@view.private["finance"]["debt"]),
                value2: money(@view.private["finance"]["available"]),
                value3: @view.private["account"]["bankruptcies"]
              )}
            </p>
            <details id="loan-terms" phx-mounted={JS.ignore_attributes("open")}>
              <summary class="cursor-pointer">{gettext("Loan terms")}</summary>
              <p class="mt-2 text-sm">
                {gettext(
                  "New loans have %{value1} installments and accrue %{value2}% interest per %{value3} active-world hours on outstanding principal, continuously while the world runs. Recent bankruptcies raise rates from 8% to 9%, 10%, 12%, 14%, then 16%; existing loans keep their rate. Early repayment has no penalty and avoids future interest. Borrowing is not profit.",
                  value1: @view.private["finance"]["installments"],
                  value2:
                    @view.private[
                      "finance"
                    ]["rate_bps"] / 100,
                  value3:
                    div(
                      @view.private["finance"]["period_ms"],
                      3_600_000
                    )
                )}
              </p>
            </details>
            <p :if={@view.private["finance"]["deadline"]} class="text-amber-300">
              {gettext(
                "Arrears: %{value1}. Bankruptcy deadline in %{value2} active-world minutes. World suspension pauses this countdown.",
                value1: money(@view.private["finance"]["arrears"]),
                value2:
                  minutes(max(0, @view.private["finance"]["deadline"] - @view.public["clock_ms"]))
              )}
            </p>
            <.form
              for={%{}}
              id="loan-form"
              phx-submit="borrow"
              phx-hook="LoanAmount"
              data-max={div(@view.private["finance"]["available"], 100)}
              class="flex flex-wrap items-center gap-2"
            >
              <input
                type="range"
                aria-label={gettext("Loan amount in $10,000 steps")}
                min="0"
                max={ceil(div(@view.private["finance"]["available"], 100) / 10_000)}
                step="1"
                value={ceil(div(@view.private["finance"]["available"], 100) / 10_000)}
                disabled={@view.private["finance"]["available"] < 100}
                class="w-full accent-teal-500"
              />
              <input type="hidden" name="request_id" value={@request_id} />
              <input
                type="number"
                name="amount"
                aria-label={gettext("Loan amount in dollars")}
                disabled={@view.private["finance"]["available"] < 100}
                min="1"
                max={div(@view.private["finance"]["available"], 100)}
                value={div(@view.private["finance"]["available"], 100)}
                class="w-32 rounded bg-slate-800 p-2"
              />
              <button
                disabled={@view.private["finance"]["available"] < 100}
                phx-disable-with={gettext("Borrowing…")}
                class="rounded bg-teal-700 p-2 disabled:opacity-40"
              >{gettext("Borrow")}</button>
            </.form>
            <details
              :for={loan <- @view.private["finance"]["loans"]}
              :if={loan["status"] == "open"}
              id={"loan-" <> loan["id"]}
              phx-mounted={JS.ignore_attributes("open")}
              class="rounded border border-slate-600 p-2"
            >
              <summary>
                {gettext(
                  "%{value1} loan · %{value2}% per period · %{value3} · %{value4} principal remaining",
                  value1: money(loan["principal"]),
                  value2: loan["rate_bps"] / 100,
                  value3:
                    loan[
                      "status"
                    ],
                  value4: money(loan["remaining"])
                )}
              </summary>
              <p>
                {gettext("Accrued interest not yet due: %{value1} · Currently due: %{value2}",
                  value1: finance_money(loan["interest_accrued"]),
                  value2: money(loan["principal_due"] + loan["interest_due"])
                )}
              </p>
              <table :if={loan["status"] == "open"} class="w-full text-right">
                <caption class="pb-2 text-left">
                  {gettext("Projected schedule assuming timely payments in active-world time:")}
                </caption><thead>
                  <tr>
                    <th title={
                      gettext(
                        "Remaining active-world time (HH:MM:SS); pauses when the world is suspended"
                      )
                    }>
                      {gettext("Due in (HH:MM:SS)")}
                    </th><th>{gettext("Principal")}</th><th>{gettext("Interest")}</th>
                  </tr>
                </thead><tbody>
                  <tr :for={row <- loan["schedule"]}>
                    <td>
                      <bdi dir="ltr">{active_countdown(row["due_ms"] - @view.public["clock_ms"])}</bdi>
                    </td><td>
                      {money(row["principal"])}
                    </td><td>{finance_money(row["interest"])}</td>
                  </tr>
                </tbody>
              </table>
              <% actions = loan["actions"] %>
              <% recast_min = div(actions["recast_min"] + 99, 100) %>
              <% recast_max = div(actions["recast_max"], 100) %>
              <% can_recast = actions["recast_enabled"] && recast_max >= recast_min %>
              <% can_repay = actions["repay_enabled"] %>

              <div class="my-3 flex flex-wrap items-end gap-3">
                <.form
                  :if={can_repay}
                  for={%{}}
                  phx-submit="repay"
                  class="shrink-0"
                >
                  <input type="hidden" name="request_id" value={@request_id} /><input
                    type="hidden"
                    name="loan"
                    value={loan["id"]}
                  />
                  <button phx-disable-with={gettext("Repaying…")} class="rounded border p-2">{gettext(
                    "Repay"
                  )}<br />{finance_money(
                    loan["remaining"] + loan["interest_due"] + loan["interest_accrued"]
                  )}<br />{gettext("in full")}</button>
                </.form>
                <.form
                  :if={can_recast}
                  for={%{}}
                  id={"recast-" <> loan["id"]}
                  phx-submit="recast"
                  phx-hook="LoanAmount"
                  data-max={recast_max}
                  class="min-w-0 flex-[1_1_16rem] space-y-2"
                >
                  <input type="hidden" name="request_id" value={@request_id} />
                  <input type="hidden" name="loan" value={loan["id"]} />
                  <input
                    type="range"
                    aria-label={gettext("Recast payment in $10,000 steps")}
                    min={div(recast_min, 10_000)}
                    max={ceil(recast_max / 10_000)}
                    step="1"
                    value={ceil(min(recast_max, max(recast_min, 10_000)) / 10_000)}
                    class="w-full accent-teal-500"
                  />
                  <div class="flex flex-wrap items-start gap-3">
                    <span :if={can_repay} class="text-slate-400">{gettext("or")}</span>
                    <input
                      type="number"
                      name="amount"
                      aria-label={gettext("Recast payment in dollars")}
                      min={recast_min}
                      max={recast_max}
                      value={min(recast_max, max(recast_min, 10_000))}
                      class="w-32 rounded bg-slate-800 p-2"
                    />
                    <button phx-disable-with={gettext("Recasting…")} class="rounded border p-2">{gettext(
                      "Recast loan"
                    )}</button>
                  </div>
                </.form>
              </div>
              <p :if={can_recast} class="mt-2 text-sm">
                {gettext(
                  "Recast: pay accrued interest first, then principal. Smaller remaining installments, same payoff date and interest rate. Keep cash for trading."
                )}
              </p>
            </details>
            <.form
              :if={@view.private["finance"]["can_declare_bankruptcy"]}
              for={%{}}
              phx-submit="bankruptcy"
            >
              <input type="hidden" name="request_id" value={@request_id} />
              <button
                data-confirm={
                  gettext(
                    "Declare bankruptcy? This closes your company, forfeits access to its assets, and starts a 20-minute world-clock cooldown before a new company starting with no cash or ships."
                  )
                }
                phx-disable-with={gettext("Declaring…")}
                class="rounded border border-red-500 p-2"
              >{gettext("Declare bankruptcy")}</button>
            </.form>
          </section>
        </section>
      </div>
    </details>
    """
  end
end
