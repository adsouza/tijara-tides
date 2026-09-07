defmodule Docs.PortsRosterTest do
  @moduledoc """
  Guards the invariants that `docs/ports.md` states about itself.

  The roster's coverage table is derived from its trade-role tables, so a hand
  edit to a single role can silently invalidate it — the counts sit in a
  separate table with nothing tying them to the data. This test re-derives them.

  Parsing is deliberately structural rather than positional: a trade-role table
  is recognised by every body cell holding one of the five role codes, and the
  physical table by having a Reefer column. Renaming a heading or reordering
  sections therefore cannot quietly disable a check. The failure mode that
  matters for a document checker is matching nothing and passing anyway, so the
  roster test asserts the parsed shape before it asserts the invariants.
  """
  use ExUnit.Case, async: true

  @roster "docs/ports.md"

  @roles_only """
  ### Bulk commodities

  | Port | Iron ore | Grain |
  |------|----------|-------|
  | Alpha | `++exp` | `—` |
  | Bravo | `—` | `++imp` |
  | Charlie | `—` | `++exp` |
  """

  @thin_exports """
  ### Perishables

  | Port | Widgets |
  |------|---------|
  | Alpha | `++exp` |
  | Bravo | `++imp` |
  | Charlie | `++imp` |
  | Delta | `++imp` |
  | Echo | `++imp` |
  """

  @thin_bulk """
  ### Bulk commodities

  | Port | Iron ore |
  |------|----------|
  | Alpha | `++exp` |
  | Bravo | `+exp` |
  | Charlie | `+exp` |
  | Delta | `++imp` |
  | Echo | `++imp` |
  | Foxtrot | `++imp` |
  | Golf | `++imp` |
  | Hotel | `++imp` |
  """

  @dead_ends """
  | Port | Widgets | Gadgets |
  |------|---------|---------|
  | Alpha | `++exp` | `+exp` |
  | Bravo | `++imp` | `++imp` |
  """

  @one_way_tankers """
  | Port | Crude oil | Refined fuel |
  |------|-----------|--------------|
  | Alpha | `++exp` | `++exp` |
  | Bravo | `++imp` | `++imp` |
  """

  @twin_cluster """
  - **Twin Delta:** Alpha, Bravo

  | Port | Widgets | Gadgets | Trinkets | Baubles |
  |------|---------|---------|----------|---------|
  | Alpha | `++exp` | `++exp` | `++imp` | `++imp` |
  | Bravo | `++exp` | `++exp` | `++imp` | `+imp` |
  """

  @abundant_reefer """
  | Port | Berths | Ordinary | Reefer | Liquid | Handling | Cost | Max size |
  |------|--------|----------|--------|--------|----------|------|----------|
  | Alpha | high | high | high | high | fast | high | any |
  | Bravo | high | high | high | high | fast | high | any |
  | Charlie | high | high | low | high | fast | high | any |
  """

  test "flags a good that only one port trades" do
    assert @roles_only |> parse() |> check_exclusive() == ["Iron ore is traded only at Alpha"]
  end

  test "flags a good with too few exporters" do
    assert @thin_exports |> parse() |> check_minimums() ==
             ["Widgets has 1 exporter(s), needs at least 3"]
  end

  test "holds bulk commodities to a higher minimum than other categories" do
    assert @thin_bulk |> parse() |> check_minimums() ==
             ["Iron ore has 3 exporter(s), needs at least 5"]
  end

  test "flags ports that cannot make a round trip" do
    assert @dead_ends |> parse() |> check_round_trips() ==
             ["Alpha imports nothing", "Bravo exports nothing"]
  end

  test "flags tanker trades that cannot run in both directions" do
    assert @one_way_tankers |> parse() |> check_tanker_directions() ==
             [
               "no port exports crude oil while importing refined fuel",
               "no port exports refined fuel while importing crude oil"
             ]
  end

  test "flags clustered ports that barely differ" do
    assert @twin_cluster |> parse() |> check_cluster_spread() ==
             ["Twin Delta: Alpha and Bravo differ in only 1 of 4 trade roles"]
  end

  test "flags refrigerated capacity that is not scarce" do
    assert @abundant_reefer |> parse() |> check_reefer_scarcity() ==
             ["2 of 3 ports have high refrigerated capacity; fewer than half should"]
  end

  @no_liquid_backhaul """
  | Port | Refined fuel | Vegetable oil |
  |------|--------------|---------------|
  | Alpha | `++exp` | `++exp` |
  | Bravo | `++imp` | `++imp` |
  """

  test "flags a liquid catalogue that leaves tankers no counter-flow" do
    assert @no_liquid_backhaul |> parse() |> check_liquid_backhaul() ==
             ["no port imports refined fuel while exporting vegetable oil"]
  end

  test "the committed roster satisfies every invariant" do
    parsed = @roster |> File.read!() |> parse()

    # A parser that matched nothing would satisfy every check below vacuously.
    assert length(parsed.goods) == 21, "parsed #{length(parsed.goods)} goods, expected 21"
    assert map_size(parsed.roles) == 25, "parsed #{map_size(parsed.roles)} ports, expected 25"
    assert map_size(parsed.tiers) == 25, "parsed #{map_size(parsed.tiers)} tier rows"
    assert map_size(parsed.clusters) == 3, "parsed #{map_size(parsed.clusters)} clusters"

    assert violations(parsed) == [],
           "#{@roster} breaks its own invariants:\n  " <> Enum.join(violations(parsed), "\n  ")
  end

  # -- parsing ---------------------------------------------------------------

  @not_traded "—"
  @exports ["++exp", "+exp"]
  @imports ["+imp", "++imp"]
  @codes @exports ++ @imports ++ [@not_traded]

  defp parse(markdown) do
    tables = markdown |> String.split("\n") |> table_blocks()
    role_tables = Enum.filter(tables, fn {_category, table} -> role_table?(table) end)

    %{
      goods: for({_c, {goods, _rows}} <- role_tables, good <- goods, do: good),
      category: for({c, {goods, _r}} <- role_tables, g <- goods, into: %{}, do: {g, c}),
      roles: roles(role_tables),
      clusters: clusters(markdown),
      tiers: tiers(tables)
    }
  end

  defp roles(role_tables) do
    for {_category, {goods, rows}} <- role_tables,
        {port, cells} <- rows,
        {good, role} <- Enum.zip(goods, cells),
        reduce: %{} do
      acc -> Map.update(acc, port, %{good => role}, &Map.put(&1, good, role))
    end
  end

  # "- **Pearl River Delta:** Hong Kong, Shenzhen, Guangzhou"
  defp clusters(markdown) do
    ~r/^- \*\*(?<name>[^*]+):\*\*\s*(?<ports>.+)$/m
    |> Regex.scan(markdown, capture: :all_names)
    |> Map.new(fn [name, ports] ->
      {name, ports |> String.split(",") |> Enum.map(&String.trim/1)}
    end)
  end

  defp tiers(tables) do
    Enum.find_value(tables, %{}, fn {_category, {columns, rows}} ->
      if "Reefer" in columns do
        Map.new(rows, fn {port, values} -> {port, Map.new(Enum.zip(columns, values))} end)
      end
    end)
  end

  # Tables carry the `###` heading above them, so a check can tell a bulk
  # commodity from a perishable without hard-coding good names.
  defp table_blocks(lines) do
    {blocks, heading, pending} =
      Enum.reduce(lines, {[], nil, []}, fn line, {blocks, heading, pending} ->
        cond do
          table_row?(line) -> {blocks, heading, pending ++ [line]}
          subheading?(line) -> {flush(blocks, heading, pending), heading_text(line), []}
          true -> {flush(blocks, heading, pending), heading, []}
        end
      end)

    Enum.reverse(flush(blocks, heading, pending))
  end

  defp flush(blocks, heading, pending) when length(pending) >= 3,
    do: [{heading, as_table(pending)} | blocks]

  defp flush(blocks, _heading, _pending), do: blocks

  defp table_row?(line), do: String.starts_with?(String.trim(line), "|")
  defp subheading?(line), do: String.starts_with?(String.trim(line), "###")

  defp heading_text(line),
    do: line |> String.trim() |> String.trim_leading("#") |> String.trim()

  defp as_table([header, _separator | rows]) do
    [_port_column | goods] = cells(header)
    {goods, Enum.map(rows, fn row -> {hd(cells(row)), tl(cells(row))} end)}
  end

  defp cells(line) do
    line
    |> String.trim()
    |> String.trim("|")
    |> String.split("|")
    |> Enum.map(&(&1 |> String.trim() |> String.trim("`")))
  end

  defp role_table?({goods, rows}) do
    goods != [] and
      Enum.all?(rows, fn {_port, cells} ->
        length(cells) == length(goods) and Enum.all?(cells, &(&1 in @codes))
      end)
  end

  # -- checks ----------------------------------------------------------------

  defp violations(parsed) do
    check_exclusive(parsed) ++
      check_minimums(parsed) ++
      check_round_trips(parsed) ++
      check_tanker_directions(parsed) ++
      check_liquid_backhaul(parsed) ++
      check_cluster_spread(parsed) ++
      check_reefer_scarcity(parsed)
  end

  defp check_exclusive(%{goods: goods, roles: roles}) do
    for good <- goods,
        traders = ports_where(roles, good, &(&1 != @not_traded)),
        length(traders) == 1,
        do: "#{good} is traded only at #{hd(traders)}"
  end

  defp check_minimums(%{goods: goods, category: category, roles: roles}) do
    for good <- goods,
        {least_exp, least_imp} = minimums_for(Map.get(category, good)),
        shortfall <- [
          shortfall(good, "exporter", ports_where(roles, good, &(&1 in @exports)), least_exp),
          shortfall(good, "importer", ports_where(roles, good, &(&1 in @imports)), least_imp)
        ],
        shortfall != nil,
        do: shortfall
  end

  defp minimums_for("Bulk commodities"), do: {5, 5}
  defp minimums_for(_other), do: {3, 4}

  defp shortfall(good, role, ports, least) when length(ports) < least,
    do: "#{good} has #{length(ports)} #{role}(s), needs at least #{least}"

  defp shortfall(_good, _role, _ports, _least), do: nil

  defp check_round_trips(%{roles: roles}) do
    for {port, by_good} <- Enum.sort(roles),
        {direction, codes} <- [{"exports", @exports}, {"imports", @imports}],
        not Enum.any?(Map.values(by_good), &(&1 in codes)),
        do: "#{port} #{direction} nothing"
  end

  # Tankers only pay if they load at both ends: somewhere must ship crude and
  # take fuel back, and somewhere must refine crude into fuel.
  defp check_tanker_directions(%{goods: goods, roles: roles}) do
    if "Crude oil" in goods and "Refined fuel" in goods do
      for {out, back} <- [{"Crude oil", "Refined fuel"}, {"Refined fuel", "Crude oil"}],
          not Enum.any?(roles, fn {_port, by_good} ->
            by_good[out] in @exports and by_good[back] in @imports
          end),
          do: "no port exports #{String.downcase(out)} while importing #{String.downcase(back)}"
    else
      []
    end
  end

  # Vegetable oil exists so a tanker delivering fuel has something to load for
  # the return leg; that only holds while the two flow in opposite directions.
  defp check_liquid_backhaul(%{goods: goods, roles: roles}) do
    fuel = "Refined fuel"
    veg = "Vegetable oil"

    if fuel in goods and veg in goods do
      if Enum.any?(roles, fn {_port, by_good} ->
           by_good[fuel] in @imports and by_good[veg] in @exports
         end),
         do: [],
         else: ["no port imports refined fuel while exporting vegetable oil"]
    else
      []
    end
  end

  # Correlated prices leave specialization as a cluster's only distinction, so
  # ports sharing a catchment must not converge on the same trade roles.
  defp check_cluster_spread(%{clusters: clusters, roles: roles}) do
    for {name, members} <- Enum.sort(clusters),
        [a, b] <- pairs(Enum.filter(members, &Map.has_key?(roles, &1))),
        shared = shared_roles(roles[a], roles[b]),
        total = map_size(roles[a]),
        total - shared < div(total, 2),
        do: "#{name}: #{a} and #{b} differ in only #{total - shared} of #{total} trade roles"
  end

  defp pairs(items) do
    for {a, i} <- Enum.with_index(items), {b, j} <- Enum.with_index(items), i < j, do: [a, b]
  end

  defp shared_roles(a, b), do: Enum.count(a, fn {good, role} -> b[good] == role end)

  defp check_reefer_scarcity(%{tiers: tiers}) when map_size(tiers) > 0 do
    high = Enum.count(tiers, fn {_port, values} -> values["Reefer"] == "high" end)
    total = map_size(tiers)

    if high * 2 > total,
      do: ["#{high} of #{total} ports have high refrigerated capacity; fewer than half should"],
      else: []
  end

  defp check_reefer_scarcity(_parsed), do: []

  defp ports_where(roles, good, predicate) do
    roles
    |> Enum.filter(fn {_port, by_good} -> predicate.(Map.fetch!(by_good, good)) end)
    |> Enum.map(fn {port, _by_good} -> port end)
    |> Enum.sort()
  end
end
