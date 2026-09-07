defmodule Docs.ShipInstructionsTest do
  use ExUnit.Case, async: true

  @leaking_reservation """
  ## Example lifecycle

  | State | Kind | Meaning |
  |-------|------|---------|
  | Idle | initial | nothing pending |
  | Held | — | holding a reservation |
  | Done | terminal | finished |

  | From | Event | Guard | To | Effects |
  |------|-------|-------|----|---------|
  | Idle | start | — | Held | `reserve cash` |
  | Held | finish | — | Done | — |

  | Reservation | Held in states |
  |-------------|----------------|
  | cash | Held |
  """

  test "flags a reservation with no release path from a state that holds it" do
    assert @leaking_reservation |> parse() |> check_release_paths() ==
             ["cash can be held in Held with no path that releases or commits it"]
  end

  @unreachable_state """
  ## Example lifecycle

  | State | Kind | Meaning |
  |-------|------|---------|
  | Idle | initial | start here |
  | Orphan | — | nothing leads here |
  | Done | terminal | finished |

  | From | Event | Guard | To | Effects |
  |------|-------|-------|----|---------|
  | Idle | finish | — | Done | — |
  | Orphan | finish | — | Done | — |
  """

  @undeclared_terminal """
  ## Example lifecycle

  | State | Kind | Meaning |
  |-------|------|---------|
  | Idle | initial | start here |
  | Stuck | — | no way out |

  | From | Event | Guard | To | Effects |
  |------|-------|-------|----|---------|
  | Idle | wedge | — | Stuck | — |
  """

  test "flags a state unreachable from the lifecycle's initial state" do
    assert @unreachable_state |> parse() |> check_reachability() ==
             ["Orphan is unreachable from Idle"]
  end

  test "flags a dead end that is not declared terminal" do
    assert @undeclared_terminal |> parse() |> check_terminals() ==
             ["Stuck has no outgoing transitions but is not declared terminal"]
  end

  @ambiguous_transition """
  ## Example lifecycle

  | State | Kind | Meaning |
  |-------|------|---------|
  | Idle | initial | start here |
  | Done | terminal | finished |

  | From | Event | Guard | To | Effects |
  |------|-------|-------|----|---------|
  | Idle | finish | — | Done | — |
  | Idle | finish | funds available | Done | — |
  """

  @handled_and_rejected """
  ## Example lifecycle

  | State | Kind | Meaning |
  |-------|------|---------|
  | Idle | initial | start here |
  | Done | terminal | finished |

  | From | Event | Guard | To | Effects |
  |------|-------|-------|----|---------|
  | Idle | finish | — | Done | — |

  | State | Event | Guard | Why |
  |-------|-------|-------|-----|
  | Idle | finish | — | cannot finish before starting |
  """

  @diagram_drift """
  ## Example lifecycle

  ```mermaid
  stateDiagram-v2
      [*] --> Idle
      Idle --> Done: finish
      Idle --> Ghost: phantom
  ```

  | State | Kind | Meaning |
  |-------|------|---------|
  | Idle | initial | start here |
  | Done | terminal | finished |

  | From | Event | Guard | To | Effects |
  |------|-------|-------|----|---------|
  | Idle | finish | — | Done | — |
  """

  test "flags an unconditional transition competing with a guarded one" do
    assert @ambiguous_transition |> parse() |> check_determinism() ==
             ["Idle on finish has several transitions and one carries no guard"]
  end

  test "flags an event both handled and explicitly rejected in one state" do
    assert @handled_and_rejected |> parse() |> check_rejections() ==
             ["Idle on finish is both a transition and a rejection"]
  end

  test "flags a diagram edge with no matching transition" do
    assert @diagram_drift |> parse() |> check_diagram() ==
             [
               "Example lifecycle diagram has an edge with no transition: Idle -> Ghost on phantom"
             ]
  end

  @tables "docs/ship-instructions.md"

  test "a release on one branch cannot hide a leaking terminal branch" do
    parsed = parse(@leaking_reservation)

    good_exit = %{
      "From" => "Held",
      "Event" => "cancel",
      "Guard" => "—",
      "To" => "Done",
      "Effects" => "release cash"
    }

    parsed = update_in(parsed, ["Example lifecycle", :transitions], &[good_exit | &1])
    assert check_release_paths(parsed) == []

    assert check_reservation_exits(parsed) ==
             [
               "Example lifecycle: Held on finish exits to Done without releasing or committing cash"
             ]
  end

  test "budget adopts successful funding rather than reserving independently on request" do
    tables = @tables |> File.read!() |> parse()
    budget = tables["Earmarked purchase budget"]
    assert transitions(budget, "Unreserved", "departure_due") == []
    funded = transitions(budget, "Unreserved", "funding_resolved")
    assert Enum.any?(funded, &(&1["To"] == "ReservedForVisit"))
    refute Enum.any?(funded, &String.contains?(&1["Effects"], "reserve purchase budget"))

    # Immediate, retried, and accumulated departures all reach the same handoff.
    funding = tables["Departure funding"]

    for state <- ["Requesting", "Blocked", "Accumulating", "Cooldown"] do
      assert Enum.any?(funding.transitions, &(&1["From"] == state and &1["To"] == "Departed"))
    end
  end

  test "successful accumulation transfers its balance and cooldown permits affordable departure" do
    funding = (@tables |> File.read!() |> parse())["Departure funding"]
    [success] = transitions(funding, "Accumulating", "funds_or_settings_changed")
    assert frees?(success["Effects"], "accumulated cash")

    broken = %{
      funding
      | transitions:
          List.delete(funding.transitions, success) ++
            [%{success | "Effects" => "reserve fuel; reserve purchase budget"}]
    }

    assert check_reservation_exits(%{"Departure funding" => broken}) != []

    retry = transitions(funding, "Cooldown", "funds_or_settings_changed")
    assert Enum.any?(retry, &(&1["To"] == "Departed"))
    assert Enum.any?(retry, &(&1["To"] == "Cooldown"))
  end

  test "wait limit is handled in every port phase without starting another handling phase" do
    tables = @tables |> File.read!() |> parse()
    visit = tables["Stop visit"]
    [cancel] = transitions(tables["Linked remote buy order"], "Active", "wait_limit_reached")
    assert frees?(cancel["Effects"], "remote order cash")
    assert frees?(cancel["Effects"], "remote order capacity")

    for state <- ["AwaitingBerth", "Unloading", "Loading", "Waiting"] do
      timeout = transitions(visit, state, "wait_limit_reached")
      assert timeout != [], "#{state} ignores the visit deadline"
      assert Enum.all?(timeout, &(&1["To"] in ["Finished", "FinishingHandling"]))
    end

    [drain] = transitions(visit, "FinishingHandling", "handling_complete")
    assert drain["To"] == "Finished"

    refute Enum.any?(
             visit.transitions,
             &(&1["From"] == "FinishingHandling" and
                 &1["To"] in ["Unloading", "Loading", "AwaitingBerth"])
           )
  end

  test "cancellation and pre-berth completion release budgets and linked resources" do
    tables = @tables |> File.read!() |> parse()
    budget = tables["Earmarked purchase budget"]

    for state <- ["ReservedForVisit", "InUseAtBerth"] do
      [cancel] = transitions(budget, state, "stop_removed")
      assert cancel["To"] == "Released"
      assert frees?(cancel["Effects"], "purchase budget")
    end

    for {name, state, reservation} <- [
          {"Earmarked purchase budget", "ReservedForVisit", "purchase budget"},
          {"Linked remote buy order", "Active", "remote order cash"},
          {"Linked remote buy order", "Active", "remote order capacity"},
          {"Advance collection reservation", "Reserved", "reserved stock"}
        ] do
      [finish] = transitions(tables[name], state, "visit_finished")
      assert frees?(finish["Effects"], reservation)
    end
  end

  test "a full hold preserves outstanding sale or unload targets" do
    visit = (@tables |> File.read!() |> parse())["Stop visit"]
    exhausted = transitions(visit, "Loading", "capacity_exhausted")

    assert Enum.any?(
             exhausted,
             &(&1["To"] == "Waiting" and
                 &1["Guard"] == "sale or unload targets remain; no handling remains")
           )

    assert Enum.any?(
             exhausted,
             &(&1["To"] == "Finished" and
                 &1["Guard"] ==
                   "sale and unload targets resolved; only loading is capacity-blocked; no handling remains")
           )

    refute Enum.any?(exhausted, &(&1["Guard"] == "—"))
  end

  defp transitions(lifecycle, state, event) do
    Enum.filter(lifecycle.transitions, &(&1["From"] == state and &1["Event"] == event))
  end

  test "the committed state tables satisfy every invariant" do
    lifecycles = @tables |> File.read!() |> parse()

    # A parser that matched nothing would satisfy every check below vacuously.
    assert map_size(lifecycles) == 5, "parsed #{map_size(lifecycles)} lifecycles, expected 5"

    assert Enum.all?(lifecycles, fn {_name, l} -> l.states != [] and l.transitions != [] end),
           "a lifecycle parsed with no states or no transitions"

    faults =
      check_release_paths(lifecycles) ++
        check_reservation_exits(lifecycles) ++
        check_reachability(lifecycles) ++
        check_terminals(lifecycles) ++
        check_determinism(lifecycles) ++
        check_rejections(lifecycles) ++
        check_diagram(lifecycles) ++
        check_effect_vocabulary(lifecycles)

    assert faults == [], "#{@tables} breaks its own invariants:\n  " <> Enum.join(faults, "\n  ")
  end

  # -- parsing ---------------------------------------------------------------
  #
  # Lifecycles are `##` sections. Each carries up to four tables, recognised by
  # their header rather than their order, so adding or reordering sections
  # cannot silently disable a check.

  @state_header ~w(State Kind Meaning)
  @transition_header ~w(From Event Guard To Effects)
  @rejection_header ~w(State Event Guard Why)
  @reservation_header ["Reservation", "Held in states"]

  # A `##` section is a lifecycle only if it declares states, so the document's
  # closing prose sections are not mistaken for one.
  defp parse(markdown) do
    markdown
    |> String.split(~r/^## /m)
    |> Enum.drop(1)
    |> Enum.map(&lifecycle/1)
    |> Enum.reject(fn {_name, lifecycle} -> lifecycle.states == [] end)
    |> Map.new()
  end

  defp lifecycle(section) do
    [heading | _] = String.split(section, "\n", parts: 2)
    tables = tables(section)

    {String.trim(heading),
     %{
       states: rows(tables, @state_header),
       transitions: rows(tables, @transition_header),
       rejections: rows(tables, @rejection_header),
       reservations: rows(tables, @reservation_header),
       edges: edges(section)
     }}
  end

  defp tables(section) do
    section
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
      if columns == header, do: Enum.map(body, &(Enum.zip(header, &1) |> Map.new()))
    end)
  end

  # `A --> B: event` inside a mermaid block. The `[*]` pseudo-state carries no
  # event and is checked through the initial-state declaration instead.
  defp edges(section) do
    ~r/^\s*(?<from>[^\s\[][^\s]*)\s*-->\s*(?<to>[^\s:]+)\s*:\s*(?<event>.+)$/m
    |> Regex.scan(section, capture: :all_names)
    |> Enum.map(fn [event, from, to] ->
      %{"From" => String.trim(from), "To" => String.trim(to), "Event" => String.trim(event)}
    end)
  end

  defp cells(line) do
    line
    |> String.trim()
    |> String.trim("|")
    |> String.split("|")
    |> Enum.map(&(&1 |> String.trim() |> String.trim("`")))
  end

  # -- checks ----------------------------------------------------------------

  defp check_reachability(lifecycles) do
    for {_name, lifecycle} <- Enum.sort(lifecycles),
        initial = kind_of(lifecycle, "initial"),
        initial != nil,
        reached = walk(lifecycle, [initial], MapSet.new([initial])),
        state <- declared_states(lifecycle),
        not MapSet.member?(reached, state),
        do: "#{state} is unreachable from #{initial}"
  end

  defp walk(_lifecycle, [], reached), do: reached

  defp walk(lifecycle, [state | rest], reached) do
    next =
      lifecycle.transitions
      |> Enum.filter(&(&1["From"] == state))
      |> Enum.map(& &1["To"])
      |> Enum.reject(&MapSet.member?(reached, &1))

    walk(lifecycle, rest ++ next, Enum.into(next, reached))
  end

  # A dead end that nobody declared terminal is an accident, not a design.
  #
  # The faults are computed in a helper rather than bound inside the
  # comprehension: a bare `flag = false` step reads as a failed filter and would
  # silently drop the non-terminal states this is meant to catch.
  defp check_terminals(lifecycles) do
    for {_name, lifecycle} <- Enum.sort(lifecycles),
        state <- declared_states(lifecycle),
        fault <- terminal_faults(lifecycle, state),
        do: fault
  end

  defp terminal_faults(lifecycle, state) do
    outgoing = Enum.count(lifecycle.transitions, &(&1["From"] == state))
    terminal? = kind(lifecycle, state) == "terminal"

    cond do
      outgoing == 0 and not terminal? ->
        ["#{state} has no outgoing transitions but is not declared terminal"]

      outgoing > 0 and terminal? ->
        ["#{state} is declared terminal but has outgoing transitions"]

      true ->
        []
    end
  end

  # Guards cannot be evaluated here, but an unconditional transition alongside a
  # guarded one on the same event makes the guarded one unreachable regardless
  # of what the guard says.
  defp check_determinism(lifecycles) do
    for {_name, lifecycle} <- Enum.sort(lifecycles),
        {{from, event}, group} <- Enum.group_by(lifecycle.transitions, &{&1["From"], &1["Event"]}),
        fault <- determinism_faults(from, event, group),
        do: fault
  end

  defp determinism_faults(from, event, group) do
    guards = Enum.map(group, & &1["Guard"])

    cond do
      length(Enum.uniq(guards)) < length(guards) ->
        ["#{from} on #{event} has two transitions with the same guard"]

      length(group) > 1 and Enum.any?(guards, &(&1 in ["", "—"])) ->
        ["#{from} on #{event} has several transitions and one carries no guard"]

      true ->
        []
    end
  end

  # An event may be handled under one guard and rejected under another, so only
  # an identical guard on both sides is a contradiction.
  defp check_rejections(lifecycles) do
    for {_name, lifecycle} <- Enum.sort(lifecycles),
        rejection <- lifecycle.rejections,
        Enum.any?(lifecycle.transitions, fn transition ->
          transition["From"] == rejection["State"] and
            transition["Event"] == rejection["Event"] and
            transition["Guard"] == rejection["Guard"]
        end),
        do: "#{rejection["State"]} on #{rejection["Event"]} is both a transition and a rejection"
  end

  # The diagram is generated from the transitions, so any disagreement means the
  # document was edited by hand rather than regenerated.
  defp check_diagram(lifecycles) do
    for {name, lifecycle} <- Enum.sort(lifecycles),
        fault <- diagram_faults(name, lifecycle),
        do: fault
  end

  defp diagram_faults(name, lifecycle) do
    key = fn row -> {row["From"], row["To"], row["Event"]} end
    declared = MapSet.new(lifecycle.transitions, key)
    drawn = MapSet.new(lifecycle.edges, key)

    missing =
      for {from, to, event} <- MapSet.difference(drawn, declared),
          do: "#{name} diagram has an edge with no transition: #{from} -> #{to} on #{event}"

    undrawn =
      for {from, to, event} <- MapSet.difference(declared, drawn),
          do: "#{name} diagram is missing an edge: #{from} -> #{to} on #{event}"

    Enum.sort(missing) ++ Enum.sort(undrawn)
  end

  defp declared_states(lifecycle), do: Enum.map(lifecycle.states, & &1["State"])

  defp kind(lifecycle, state) do
    Enum.find_value(lifecycle.states, fn row -> row["State"] == state && row["Kind"] end)
  end

  defp kind_of(lifecycle, kind) do
    Enum.find_value(lifecycle.states, fn row -> row["Kind"] == kind && row["State"] end)
  end

  # A misspelled reservation name would make a release invisible to the check
  # above, reporting a leak that is not there or, worse, hiding one that is.
  defp check_effect_vocabulary(lifecycles) do
    declared =
      for {_name, lifecycle} <- lifecycles,
          reservation <- lifecycle.reservations,
          into: MapSet.new(),
          do: reservation["Reservation"]

    for {name, lifecycle} <- Enum.sort(lifecycles),
        transition <- lifecycle.transitions,
        {verb, named} <- reservation_verbs(transition["Effects"]),
        not Enum.any?(declared, &String.starts_with?(named, &1)),
        do:
          "#{name}: #{transition["From"]} on #{transition["Event"]} has \"#{verb}\" " <>
            "naming no declared reservation"
  end

  defp reservation_verbs(effects) do
    ~r/\b(?<verb>reserve|release|commit)\s+(?<named>[a-z][a-z ]*)/
    |> Regex.scan(effects, capture: :all_names)
    |> Enum.map(fn [named, verb] -> {verb, String.trim(named)} end)
  end

  # Cash, stock or capacity reserved on one path and leaked on another is the
  # bug class section 8's rules exist to prevent, so every state that can hold a
  # reservation must reach a transition that releases or commits it.
  defp check_release_paths(lifecycles) do
    for {_name, lifecycle} <- Enum.sort(lifecycles),
        reservation <- lifecycle.reservations,
        held = reservation["Reservation"],
        state <- split_list(reservation["Held in states"]),
        not releases?(lifecycle, state, held, MapSet.new()),
        do: "#{held} can be held in #{state} with no path that releases or commits it"
  end

  defp releases?(lifecycle, state, reservation, seen) do
    cond do
      MapSet.member?(seen, state) ->
        false

      true ->
        seen = MapSet.put(seen, state)

        lifecycle.transitions
        |> Enum.filter(&(&1["From"] == state))
        |> Enum.any?(fn transition ->
          frees?(transition["Effects"], reservation) or
            releases?(lifecycle, transition["To"], reservation, seen)
        end)
    end
  end

  defp frees?(effects, reservation) do
    Enum.any?(["release #{reservation}", "commit #{reservation}"], &String.contains?(effects, &1))
  end

  # A release on another branch does not clear an exit that strands funds.
  # Held-state declarations describe the resource still owned by this lifecycle;
  # crossing out of that set must explicitly release or transfer the balance.
  defp check_reservation_exits(lifecycles) do
    for {name, lifecycle} <- Enum.sort(lifecycles),
        reservation <- lifecycle.reservations,
        held = reservation["Reservation"],
        states = split_list(reservation["Held in states"]),
        transition <- lifecycle.transitions,
        transition["From"] in states,
        transition["To"] not in states,
        not frees?(transition["Effects"], held),
        do:
          "#{name}: #{transition["From"]} on #{transition["Event"]} exits to " <>
            "#{transition["To"]} without releasing or committing #{held}"
  end

  defp split_list(value) do
    value |> String.split(~r/[,;]/) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end
end
