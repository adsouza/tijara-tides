defmodule TijaraTides.Localization.Notifications do
  @moduledoc "Render structured domain notices only at the presentation boundary."
  use Gettext, backend: TijaraTides.Localization.Backend
  alias TijaraTides.Localization

  def render(%{"code" => code} = notice, goods) when is_binary(code) do
    args =
      Map.new(notice["arguments"], fn
        {"cargo", good} ->
          {"cargo", Localization.text(get_in(goods, [good, "name"]) || good)}

        {key, amount} when key in ["loss", "refund"] ->
          {key, Localization.money(amount)}

        {key, value} when key in ["reason", "side", "port", "destination"] ->
          {key, Localization.text(value || "")}

        {key, value} when is_number(value) ->
          {key, Localization.number(value)}

        pair ->
          pair
      end)

    bindings =
      for key <-
            ~w(cargo loss refund reason side minutes company ship port destination filled quantity)a,
          Map.has_key?(args, Atom.to_string(key)),
          into: %{},
          do: {key, args[Atom.to_string(key)]}

    message(code, bindings)
  end

  def render(notice, _goods), do: notice["text"] || ""

  defp message("auction.closed", args),
    do:
      gettext(
        "The luxury auction at %{port} has settled. See Luxury auctions for the result.",
        args
      )

  defp message("exchange.cancelled", args),
    do:
      gettext(
        "An exchange order at %{port} was cancelled because its backing or validity expired.",
        args
      )

  defp message("warehouse.renewal_open", args),
    do: gettext("Warehouse renewal is now available at %{port}.", args)

  defp message("warehouse.reservation_released", args),
    do:
      gettext(
        "A warehouse reservation at %{port} was reduced or released because its cargo, ship, stop or lease is no longer available.",
        args
      )

  defp message("warehouse.expired", args),
    do:
      gettext(
        "Your warehouse lease at %{port} expired. Collect its cargo within 12 active-world hours.",
        args
      )

  defp message("warehouse.cleared", args),
    do: gettext("Warehouse cargo at %{port} was cleared. Net proceeds: %{refund}.", args)

  defp message("ship.loaded", args), do: gettext("%{ship} finished loading at %{port}.", args)
  defp message("ship.unloaded", args), do: gettext("%{ship} finished unloading at %{port}.", args)

  defp message("account.suspended", args),
    do:
      gettext(
        "Account suspended after five recent bankruptcies. Your original sponsor must pledge at least $50,000 to reinstate you.",
        args
      )

  defp message("account.invitee_suspended", args),
    do:
      gettext(
        "An invitee is suspended and needs your cash-backed guarantee. Review sponsor guarantees in the account menu.",
        args
      )

  defp message("invitation.accepted", args),
    do: gettext("Your invitation was accepted. Company formation is pending.", args)

  defp message("company.formed", args), do: gettext("Your invitee now runs %{company}.", args)

  defp message("ship.departed", args),
    do: gettext("%{ship} automatically departed %{port} for %{destination}.", args)

  defp message("ship.departure_wait", args),
    do: gettext("%{ship}: automatic departure to %{destination} paused. %{reason}.", args)

  defp message("instruction.updated", args),
    do:
      gettext(
        "%{ship} at %{port}: %{side} %{cargo}, %{filled}/%{quantity} lots filled. %{reason}.",
        args
      )

  defp message("finance.arrears_cleared", args),
    do:
      gettext(
        "All overdue payments have been cleared. The bankruptcy grace period has ended.",
        args
      )

  defp message("finance.arrears", args),
    do:
      gettext(
        "Payments overdue. Clear all arrears within %{minutes} active-world minutes to avoid bankruptcy.",
        args
      )

  defp message("company.bankrupt", args),
    do:
      gettext(
        "%{company} is in bankruptcy. Its assets remain in receivership. A replacement company becomes available after 20 active-world minutes.",
        args
      )

  defp message("guarantee.funded", args),
    do:
      gettext(
        "Your sponsor has funded a guarantee. Your account is reinstated; the bankruptcy restart cooldown still applies.",
        args
      )

  defp message("guarantee.settled", args),
    do:
      gettext(
        "Your guarantee has settled: %{loss} forfeited and %{refund} returned to the sponsoring company.",
        args
      )

  defp message("route.paused", args), do: gettext("%{reason}", args)
  defp message(_code, _args), do: gettext("Notification unavailable")
end
