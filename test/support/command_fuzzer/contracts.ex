defmodule TijaraTides.CommandFuzzer.Contracts do
  @moduledoc "Independent input examples shared by payload and lifecycle exploration."

  def names(limit) do
    # 47 graphemes of three code points each straddle the 140-code-point cap.
    triple = "e\u0301\u0323"
    at_cap = String.duplicate(triple, 46) <> "e\u0301"

    valid = ["A", "  Vessel  ", "تجارة", "e\u0301", "🚢", String.duplicate("x", limit), at_cap]

    invalid = [
      <<255>>,
      nil,
      false,
      42,
      [],
      %{},
      "",
      "   ",
      String.duplicate("x", limit + 1),
      String.duplicate(triple, 47),
      "a\0b",
      "a\tb",
      "a\nb",
      "a\u200Db",
      "a\u200Bb"
    ]

    Enum.map(valid, &{&1, :ok}) ++ Enum.map(invalid, &{&1, :error})
  end

  def references, do: [nil, false, 7, [], %{}, "", "unknown", String.duplicate("x", 200)]
  def forbidden, do: [0, 9, 10, 31, 127, 0x200B, 0x200D, 0x202E]

  def name_command(:company, name), do: %{"action" => "company", "name" => name}

  def name_command(:ship, name),
    do: %{"action" => "rename_ship", "ship" => "company:1", "name" => name}

  def name_command(:preset, name),
    do: %{
      "action" => "markdown_preset_save",
      "name" => name,
      "markdowns" => %{"fresh" => 100, "good" => 80, "fair" => 50, "clearance" => 20},
      "price_floor" => 0
    }

  def name_error(:company), do: :invalid_name
  def name_error(:ship), do: :ship_name_invalid
  def name_error(:preset), do: :exchange_freshness_invalid
  def limit(:company), do: 60
  def limit(_), do: 80

  # Stated independently of PlayerNames: every stored name also fits 140 code points.
  def code_point_cap, do: 140

  def name_accepted?(kind, name),
    do:
      String.length(name) <= limit(kind) and
        length(String.codepoints(name)) <= code_point_cap()
end
