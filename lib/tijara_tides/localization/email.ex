defmodule TijaraTides.Localization.Email do
  use Gettext, backend: TijaraTides.Localization.Backend
  alias TijaraTides.Localization

  def sender_name(row) do
    Localization.with_locale(row["locale"], fn -> gettext("Tijara Tides") end)
  end

  def subject(row) do
    Localization.with_locale(row["locale"], fn ->
      if row["purpose"] == "invite",
        do: gettext("Your Tijara Tides invitation"),
        else: gettext("Your Tijara Tides sign-in link")
    end)
  end

  def body(row, url, token) do
    Localization.with_locale(row["locale"], fn ->
      expiry =
        if row["purpose"] == "invite",
          do: gettext("This invitation expires after three days of active world time."),
          else: gettext("This link expires in 15 minutes.")

      gettext(
        "Open this link to verify your email and continue to Tijara Tides:\n\n%{url}\n\nUsing the desktop app? Paste this sign-in token into the app instead:\n\n%{token}\n\nThe link and token can be used only once, on one device.\n\n%{expiry}\n\nDo not share this link or token. If you did not request it, ignore this email.",
        url: url,
        token: token,
        expiry: expiry
      )
    end)
  end
end
