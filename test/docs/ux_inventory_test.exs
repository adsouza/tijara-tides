defmodule Docs.UxInventoryTest do
  use ExUnit.Case, async: true

  @design """
  ## 4. Geography

  Show ship positions and routes visually. Selecting another ship may show its
  company and ship class, but never its cargo manifest.
  """

  @drifted """
  | # | Requirement | Section | Kind | Screen |
  |---|-------------|---------|------|--------|
  | 1 | Show ship positions and routes visually. | 4 | display | World map |
  | 2 | Show a thing the design no longer says. | 4 | display | World map |

  | Screen | Purpose |
  |--------|---------|
  | World map | the shared ocean |
  """

  @orphaned """
  | # | Requirement | Section | Kind | Screen |
  |---|-------------|---------|------|--------|
  | 1 | Show ship positions and routes visually. | 4 | display | Nowhere |

  | Screen | Purpose |
  |--------|---------|
  | World map | the shared ocean |
  """

  test "flags a requirement whose quote no longer appears in the design" do
    assert @drifted |> parse() |> check_quotes(@design) ==
             ["2 quotes text absent from DESIGN.md: \"Show a thing the design no longer says.\""]
  end

  test "flags a requirement assigned to an undeclared screen, and a screen carrying nothing" do
    assert @orphaned |> parse() |> check_screens() ==
             ["1 names undeclared screen \"Nowhere\"", "World map carries no requirements"]
  end

  @bad_ids """
  | # | Requirement | Section | Kind | Screen |
  |---|-------------|---------|------|--------|
  | 1 | Show ship positions and routes visually. | 4 | display | World map |
  | 1 | Selecting another ship may show its company and ship class. | 4 | display | World map |
  | 3 | Public market orders show prices and quantities. | 4 | display | World map |

  | Screen | Purpose |
  |--------|---------|
  | World map | the shared ocean |
  """

  @stale_tripwire """
  Heuristic requirement sentences in DESIGN.md at generation: 99

  | # | Requirement | Section | Kind | Screen |
  |---|-------------|---------|------|--------|
  | 1 | Show ship positions and routes visually. | 4 | display | World map |

  | Screen | Purpose |
  |--------|---------|
  | World map | the shared ocean |
  """

  test "flags duplicate and non-contiguous requirement ids" do
    assert @bad_ids |> parse() |> check_ids() ==
             ["requirement id 1 is used more than once", "requirement ids skip 2"]
  end

  test "flags a design whose requirement-sentence count has moved" do
    assert @stale_tripwire |> parse() |> check_tripwire(@design) ==
             [
               "DESIGN.md now has 2 requirement-like sentences, recorded as 99; " <>
                 "confirm nothing was added, then regenerate"
             ]
  end

  @inventory "docs/ux-inventory.md"
  @design_source "docs/DESIGN.md"

  test "the committed inventory satisfies every invariant" do
    design = File.read!(@design_source)
    inventory = @inventory |> File.read!() |> parse()

    # A parser that matched nothing would satisfy every check below vacuously.
    assert length(inventory.requirements) > 30,
           "parsed #{length(inventory.requirements)} requirements"

    assert length(inventory.screens) > 5, "parsed #{length(inventory.screens)} screens"
    assert inventory.tripwire != nil, "no tripwire count recorded"

    faults =
      check_quotes(inventory, design) ++
        check_screens(inventory) ++
        check_ids(inventory) ++
        check_tripwire(inventory, design)

    assert faults == [],
           "#{@inventory} breaks its own invariants:\n  " <> Enum.join(faults, "\n  ")
  end

  # -- parsing ---------------------------------------------------------------
  #
  # Tables are recognised by their header, not their position, so reordering
  # sections cannot quietly disable a check.

  @requirement_header ~w(# Requirement Section Kind Screen)
  @screen_header ~w(Screen Purpose)

  defp parse(markdown) do
    tables = tables(markdown)

    %{
      requirements: rows(tables, @requirement_header),
      screens: rows(tables, @screen_header),
      tripwire: tripwire(markdown)
    }
  end

  defp tripwire(markdown) do
    case Regex.run(~r/requirement sentences in DESIGN\.md at generation: (\d+)/, markdown) do
      [_, count] -> String.to_integer(count)
      nil -> nil
    end
  end

  defp tables(markdown) do
    markdown
    |> String.split("\n")
    |> Enum.chunk_by(&String.starts_with?(String.trim(&1), "|"))
    |> Enum.filter(fn [first | _] -> String.starts_with?(String.trim(first), "|") end)
    |> Enum.filter(&(length(&1) >= 3))
    |> Enum.map(fn [header, _separator | body] ->
      {cells(header), Enum.map(body, &cells/1)}
    end)
  end

  defp rows(tables, header) do
    Enum.find_value(tables, [], fn {columns, body} ->
      if columns == header, do: Enum.map(body, &(header |> Enum.zip(&1) |> Map.new()))
    end)
  end

  defp cells(line) do
    line |> String.trim() |> String.trim("|") |> String.split("|") |> Enum.map(&String.trim/1)
  end

  # -- checks ----------------------------------------------------------------

  defp check_ids(inventory) do
    ids = Enum.map(inventory.requirements, &String.to_integer(&1["#"]))

    duplicates =
      for {id, count} <- Enum.frequencies(ids),
          count > 1,
          do: "requirement id #{id} is used more than once"

    gaps =
      for id <- 1..Enum.max(ids, fn -> 0 end)//1,
          id not in ids,
          do: "requirement ids skip #{id}"

    Enum.sort(duplicates) ++ gaps
  end

  # Verbatim quoting cannot notice a requirement ADDED to DESIGN.md later, so
  # this counts requirement-like sentences and fails when the total moves. It is
  # a tripwire, not a proof: rewording trips it too, and the answer is to look,
  # confirm nothing was added, and regenerate.
  # Inflections are spelled out, because a missing form silently lowers the
  # count: this list once held "show" but not "shows", so making a sentence more
  # imperative made the total fall. Interaction verbs earn a place only when
  # every sentence they newly match is real surface. Measured against DESIGN.md,
  # "open", "group" and "retain" match 18, 15 and 37 further sentences that are
  # overwhelmingly about open orders, berth groups and retained cargo, so they
  # stay out; the noun "warning" stays out for the same reason, since here it
  # names a timer rather than a notice. Widen this only with that check in hand.
  @requirement_words ~w(Show Shows Showing Shown show shows showing shown
                        Display Displays Displaying Displayed
                        display displays displaying displayed
                        Reveal Reveals Revealing Revealed
                        reveal reveals revealing revealed
                        Expose Exposes Exposing Exposed
                        expose exposes exposing exposed
                        Notify Notifies Notifying Notified
                        notify notifies notifying notified
                        notification notifications
                        Selecting selecting
                        Click Clicks Clickable click clicks clickable
                        Zoom Zooms Zooming zoom zooms zooming
                        warn warns warned Warned
                        visible countdown countdowns
                        label labels labelled labeled labeling Labeled Labeling)

  defp check_tripwire(%{tripwire: nil}, _design), do: []

  defp check_tripwire(inventory, design) do
    actual = count_requirement_sentences(design)

    if actual == inventory.tripwire do
      []
    else
      [
        "DESIGN.md now has #{actual} requirement-like sentences, recorded as " <>
          "#{inventory.tripwire}; confirm nothing was added, then regenerate"
      ]
    end
  end

  defp count_requirement_sentences(design) do
    design
    |> String.split("\n")
    |> Enum.reject(&(String.starts_with?(String.trim(&1), "|") or String.starts_with?(&1, "#")))
    |> Enum.join(" ")
    |> String.split(~r/(?<=[.!?])\s+/)
    |> Enum.count(fn sentence ->
      Enum.any?(@requirement_words, &(&1 in String.split(sentence, ~r/[^\w*]+/)))
    end)
  end

  # Verbatim matching is what makes the register trustworthy: a requirement
  # reworded or deleted in DESIGN.md stops matching and fails here.
  defp check_quotes(inventory, design) do
    normalised = squeeze(design)

    for requirement <- inventory.requirements,
        quote = requirement["Requirement"],
        not String.contains?(normalised, squeeze(quote)),
        do: ~s(#{requirement["#"]} quotes text absent from DESIGN.md: "#{quote}")
  end

  # DESIGN.md wraps prose, so a quoted sentence spans lines there.
  defp squeeze(text), do: text |> String.split() |> Enum.join(" ")

  defp check_screens(inventory) do
    declared = MapSet.new(inventory.screens, & &1["Screen"])
    used = MapSet.new(inventory.requirements, & &1["Screen"])

    undeclared =
      for requirement <- inventory.requirements,
          not MapSet.member?(declared, requirement["Screen"]),
          do: ~s(#{requirement["#"]} names undeclared screen "#{requirement["Screen"]}")

    empty =
      for screen <- inventory.screens,
          not MapSet.member?(used, screen["Screen"]),
          do: "#{screen["Screen"]} carries no requirements"

    undeclared ++ empty
  end
end
