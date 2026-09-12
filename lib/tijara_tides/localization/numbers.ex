defmodule TijaraTides.Localization.Numbers do
  use Cldr,
    otp_app: :tijara_tides,
    locales: ["en", "ar"],
    default_locale: "en",
    providers: [Cldr.Number],
    precompile_number_formats: ["0.###", "0.00", "0.00%", "00", "0.0"]
end
