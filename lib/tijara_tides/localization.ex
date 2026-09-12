defmodule TijaraTides.Localization do
  @moduledoc "Presentation localization shared by web and email; persisted rules and identifiers stay language independent."
  use Boundary, deps: [], exports: [Backend, Numbers, Notifications, Email, Names]
  alias TijaraTides.Localization.Backend

  def l10n(value), do: TijaraTides.Localization.Names.translate(value)
  def locales, do: [{"en", "English"}, {"ar", "العربية"}]
  def normalize(locale) when locale in ["en", "ar"], do: locale
  def normalize(_), do: "en"
  def locale, do: normalize(Gettext.get_locale(Backend))
  def put_locale(locale), do: Gettext.put_locale(Backend, normalize(locale))
  def direction(locale), do: if(normalize(locale) == "ar", do: "rtl", else: "ltr")
  def text(message, bindings \\ %{}), do: Gettext.gettext(Backend, message, bindings)
  def with_locale(locale, fun), do: Gettext.with_locale(Backend, normalize(locale), fun)

  def number(value, options \\ []) do
    TijaraTides.Localization.Numbers.Number.to_string!(
      value,
      [locale: locale(), number_system: if(locale() == "ar", do: :arab, else: :latn)] ++ options
    )
  end

  def display_number(value), do: number(value, format: "0.###")

  def money(cents, digits \\ 0) do
    number(Decimal.div(decimal(cents), 100),
      currency: :USD,
      fractional_digits: digits,
      rounding_mode: :half_up
    )
  end

  defp decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp decimal(value), do: Decimal.new(value)
end
