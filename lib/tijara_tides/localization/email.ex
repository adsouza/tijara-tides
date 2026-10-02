defmodule TijaraTides.Localization.Email do
  use Gettext, backend: TijaraTides.Localization.Backend
  alias TijaraTides.Localization

  def sender_name(row) do
    Localization.with_locale(row["locale"], fn -> gettext("Tijara Tides") end)
  end

  def subject(row) do
    Localization.with_locale(row["locale"], fn ->
      case row["purpose"] do
        "invite" -> gettext("Your Tijara Tides invitation")
        "dormancy" -> gettext("Your Tijara Tides company closure warning")
        _ -> gettext("Your Tijara Tides sign-in link")
      end
    end)
  end

  def body(row, url, token) do
    Localization.with_locale(row["locale"], fn ->
      if row["purpose"] == "dormancy" do
        deadline = DateTime.from_unix!(row["expires_ms"], :millisecond) |> DateTime.to_iso8601()

        gettext(
          "Your company will close for owner absence at %{deadline}. Sign in and return to the game before this deadline to cancel closure:\n\n%{url}\n\nAutomated routes and unattended session refreshes do not reset absence. After closure, assets enter receivership and cannot be restored. Dormant closure does not increase your bankruptcy count.",
          deadline: deadline,
          url: url
        )
      else
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
      end
    end)
  end
end
