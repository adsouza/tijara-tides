defmodule TijaraTides.LocalizationTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Localization
  alias TijaraTides.Localization.{Email, Notifications}
  alias TijaraTidesWeb.GameUI.Presentation

  test "user-facing static attributes are marked for translation" do
    for path <- Path.wildcard("lib/tijara_tides_web/**/*.{ex,heex}") do
      source = File.read!(path)

      refute Regex.match?(~r/(?:data-confirm|aria-label|placeholder|title)="[A-Za-z]/, source),
             "Unmarked user-facing attribute in #{path}"
    end
  end

  test "every extracted message has a complete Arabic translation with safe bindings" do
    root = Application.app_dir(:tijara_tides, "priv/gettext")
    template = Expo.PO.parse_file!(Path.join(root, "default.pot"))
    translated = Expo.PO.parse_file!(Path.join(root, "ar/LC_MESSAGES/default.po"))
    translations = Map.new(translated.messages, &{IO.iodata_to_binary(&1.msgid), &1})

    for message <- template.messages do
      key = IO.iodata_to_binary(message.msgid)
      assert Map.has_key?(translations, key), "Missing Arabic message: #{key}"
      translated = translations[key]

      strings =
        if is_map(translated.msgstr), do: Map.values(translated.msgstr), else: [translated.msgstr]

      if is_map(translated.msgstr), do: assert(map_size(translated.msgstr) == 6)

      required =
        Regex.scan(~r/%\{(\w+)\}/, key, capture: :all_but_first) |> List.flatten() |> MapSet.new()

      for text <- strings do
        text = IO.iodata_to_binary(text)
        assert String.trim(text) != "", "Empty Arabic translation: #{key}"

        actual =
          Regex.scan(~r/%\{(\w+)\}/, text, capture: :all_but_first)
          |> List.flatten()
          |> MapSet.new()

        assert MapSet.subset?(actual, required), "Unknown Arabic placeholder: #{key}"

        assert MapSet.subset?(MapSet.delete(required, "count"), actual),
               "Missing Arabic placeholder: #{key}"
      end
    end
  end

  test "cargo ROI localizes ratios as percentages with two decimal places" do
    Localization.with_locale("en", fn ->
      assert Presentation.cargo_roi(0.125) == "12.50%"
      assert Presentation.cargo_roi(-0.05) == "-5.00%"
      assert Presentation.cargo_roi(0) == "0.00%"
      assert Presentation.cargo_roi(nil) == "—"
    end)

    Localization.with_locale("ar", fn ->
      assert Presentation.cargo_roi(0.125) =~ "١٢٫٥٠٪"
      assert Presentation.cargo_roi(-0.05) =~ "-٥٫٠٠٪"
      assert Presentation.cargo_roi(0) =~ "٠٫٠٠٪"
      assert Presentation.cargo_roi(nil) == "—"
    end)
  end

  test "Arabic game branding is consistent in the catalog and email while English is unchanged" do
    assert Localization.with_locale("ar", fn -> Localization.text("Tijara Tides") end) ==
             "أمواج التجارة"

    assert Localization.with_locale("en", fn -> Localization.text("Tijara Tides") end) ==
             "Tijara Tides"

    for purpose <- ["login", "invite", "link"] do
      row = %{"locale" => "ar", "purpose" => purpose}
      assert Email.sender_name(row) == "أمواج التجارة"
      assert Email.subject(row) =~ "أمواج التجارة"
      refute Email.subject(row) =~ "Tijara Tides"
      assert Email.sender_name(%{row | "locale" => "en"}) == "Tijara Tides"
    end

    catalog =
      Expo.PO.parse_file!(
        Application.app_dir(:tijara_tides, "priv/gettext/ar/LC_MESSAGES/default.po")
      )

    for message <- catalog.messages, IO.iodata_to_binary(message.msgid) =~ "Tijara Tides" do
      assert IO.iodata_to_binary(message.msgstr) =~ "أمواج التجارة"
      refute IO.iodata_to_binary(message.msgstr) =~ "Tijara Tides"
    end
  end

  test "display minutes use localized digits while preserving one decimal place" do
    Localization.with_locale("en", fn ->
      assert Presentation.minutes(1_230_000) == "20.5"
      assert Presentation.minutes(60_000) == "1.0"
      assert Presentation.minutes(0) == "0.0"
    end)

    Localization.with_locale("ar", fn ->
      assert Presentation.minutes(1_230_000) == "٢٠٫٥"
      assert Presentation.minutes(60_000) == "١٫٠"
      assert Presentation.minutes(0) == "٠٫٠"
    end)
  end

  test "text sailing arrows follow reading direction" do
    assert Localization.with_locale("en", &Presentation.sailing_arrow/0) == "→"
    assert Localization.with_locale("ar", &Presentation.sailing_arrow/0) == "←"
  end

  test "loan countdowns localize padded digits without changing duration or rounding" do
    for {locale, expected} <- [
          {"en", ["00:00:00", "00:00:01", "01:02:03", "24:00:00", "100:00:00"]},
          {"ar", ["٠٠:٠٠:٠٠", "٠٠:٠٠:٠١", "٠١:٠٢:٠٣", "٢٤:٠٠:٠٠", "١٠٠:٠٠:٠٠"]}
        ] do
      Localization.with_locale(locale, fn ->
        actual =
          Enum.map([-1, 1, 3_722_001, 86_400_000, 360_000_000], &Presentation.active_countdown/1)

        assert actual == expected
      end)
    end
  end

  test "display quantities and measures use Arabic digits without changing input values" do
    Localization.with_locale("ar", fn ->
      assert Localization.display_number(500) == "٥٠٠"
      assert Localization.display_number(1609) == "١٦٠٩"
      assert Presentation.cubic_meters(2500) == "٢٫٥ م³"
      assert Presentation.cargo_volume(%{"hold" => "liquid", "volume_l" => 1000}, 3) == "٣٠٠٠ لتر"
      assert Presentation.bounded_quantity(500, 40) == 40
    end)

    Localization.with_locale("en", fn ->
      assert Localization.display_number(1609) == "1609"
      assert Presentation.cubic_meters(2500) == "2.5 m³"
    end)
  end

  test "Arabic locale is scoped to the process and restored after email rendering" do
    Localization.put_locale("en")
    english = Localization.text("Your fleet")
    assert english == "Your fleet"
    assert Email.subject(%{"locale" => "ar", "purpose" => "login"}) =~ "أمواج التجارة"
    refute Email.subject(%{"locale" => "ar", "purpose" => "login"}) =~ "sign-in"
    assert Localization.locale() == "en"
    assert Localization.with_locale("ar", fn -> Localization.text("Your fleet") end) == "أسطولك"
    assert Localization.locale() == "en"
    assert Localization.normalize("unsupported") == "en"
  end

  test "money supports fractional input and preserves whole-dollar rounding" do
    Localization.with_locale("en", fn ->
      assert Localization.money(1250) == "$13"
      assert Localization.money(22500.0) == "$225"
      assert Localization.money(227_000) == "$2,270"
      assert Localization.money(1250, 2) == "$12.50"
    end)

    arabic = Localization.with_locale("ar", fn -> Localization.money(227_000) end)
    refute arabic == "$2,270"
    assert arabic =~ "٢"
  end

  test "Arabic duration plurals include singular, dual and plural forms" do
    Localization.with_locale("ar", fn ->
      assert Presentation.invitation_time_remaining(60_000) == "دقيقة واحدة"
      assert Presentation.invitation_time_remaining(120_000) == "دقيقتان"
      assert Presentation.invitation_time_remaining(180_000) =~ "دقائق"
      assert Presentation.invitation_time_remaining(11 * 60_000) =~ "دقيقة"
    end)
  end

  test "auction wins render both legacy and explicit warehouse storage in both locales" do
    args = %{
      "cargo" => "whisky",
      "quantity" => 2,
      "price" => 10000,
      "port" => "Dubai",
      "warehouse" => 1
    }

    for locale <- ["en", "ar"] do
      Localization.with_locale(locale, fn ->
        legacy = Notifications.render(%{"code" => "auction.won", "arguments" => args}, %{})
        assert legacy =~ Notifications.storage_name("dry")
        refute legacy =~ "%{"

        refrigerated =
          Notifications.render(
            %{"code" => "auction.won", "arguments" => Map.put(args, "storage", "reefer")},
            %{}
          )

        assert refrigerated =~ Notifications.storage_name("reefer")
        refute refrigerated =~ "%{"
      end)
    end
  end

  test "structured notices retain arbitrary names and legacy messages remain readable" do
    notice = %{"code" => "company.formed", "arguments" => %{"company" => "<Ship & Co>"}}

    assert Localization.with_locale("en", fn -> Notifications.render(notice, %{}) end) ==
             "Your invitee now runs <Ship & Co>."

    arabic = Localization.with_locale("ar", fn -> Notifications.render(notice, %{}) end)
    assert arabic =~ "<Ship & Co>"
    refute arabic =~ "Your invitee"
    assert Notifications.render(%{"text" => "Older notice"}, %{}) == "Older notice"
  end

  test "Arabic email keeps credentials and actual paragraph breaks" do
    body =
      Email.body(
        %{"locale" => "ar", "purpose" => "login"},
        "https://example.com/token",
        "secret-token"
      )

    assert body =~ "\n\nhttps://example.com/token\n\n"
    assert body =~ "\n\nsecret-token\n\n"
    refute body =~ "\\n"
    refute body =~ "Open this link"
  end
end
