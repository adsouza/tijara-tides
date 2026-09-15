defmodule TijaraTides.Domain.GeneratedWorkflowsTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{Game, Fleet, Ship, PortBerths, Trade}
  alias TijaraTides.Domain.Services.BerthAllocation

  # Fixed independent seeds make each failing sequence reproducible without global RNG state.
  for seed <- 1..8 do
    test "generated trading lifecycle preserves invariants (seed #{seed})" do
      seed = unquote(seed)
      catalogue = TijaraTides.Infrastructure.GameCatalogue.all()

      catalogue =
        Enum.reduce(
          ["Jakarta", "Singapore"],
          catalogue,
          &put_in(&2, ["ports", &1, "berth_count"], 1)
        )

      state = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, catalogue)
      {:ok, state, _} = Game.seed_invite(state, "invite")
      {:ok, state, _} = Game.redeem(state, "invite", "session", %{id: "account", wall_ms: 0})

      {:ok, state, _} =
        TijaraTides.CompanyFixture.create_company(
          state,
          Game.get(state, "accounts", "account"),
          "Generated fleet",
          "Jakarta",
          "general",
          %{id: "company", catalogue: catalogue}
        )

      account = Game.get(state, "accounts", "account")
      rng = :rand.seed_s(:exsss, {seed, seed + 101, seed + 203})

      seen = %{applied: 0, berthed: false}

      {final, _rng, seen} =
        Enum.reduce(1..90, {state, rng, seen}, fn step, {before, rng, seen} ->
          step(before, rng, seen, {seed, step}, account, catalogue)
        end)

      # Every invariant below holds trivially on a world nothing happened to, so record
      # that the sequence did something: a run where each command errors is a failure,
      # not a pass. Berth state is checked as the run goes, since a ship that reached the
      # queue may have sailed again before the last step.
      assert seen.applied >= 20, "only #{seen.applied} of 90 generated actions were accepted"
      assert seen.berthed, "no generated action ever reached the berth queue"

      assert Map.get(final, :journal, []) != [],
             "no generated action ever posted to the journal"
    end
  end

  defp step(before, rng, seen, {seed, step}, account, catalogue) do
    {choice, rng} = :rand.uniform_s(6, rng)
    {number, rng} = :rand.uniform_s(3, rng)
    {quantity, rng} = :rand.uniform_s(20, rng)
    id = "company:#{number}"
    ship = Game.get(before, "ships", id)
    destination = if ship["port"] == "Jakarta", do: "Singapore", else: "Jakarta"

    result =
      case choice do
        n when n in [1, 2, 3] ->
          BerthAllocation.submit(
            before,
            account,
            %Trade{
              ship_id: id,
              good: "lumber",
              side: if(ship["port"] == "Jakarta", do: "buy", else: "sell"),
              quantity: quantity,
              limit: if(ship["port"] == "Jakarta", do: 1_000_000, else: 0),
              destination: destination
            },
            catalogue
          )

        4 ->
          Fleet.sail(before, account, id, destination, 100_000_000, catalogue)

        5 ->
          BerthAllocation.cancel(before, account, id)

        6 ->
          {:ok, Game.advance(before, 60_000, catalogue), %{}}
      end

    {after_state, seen} =
      case result do
        {:ok, next, _} -> {next, %{seen | applied: seen.applied + 1}}
        {:error, _} -> {before, seen}
      end

    fleet = TijaraTides.Domain.ReadState.entities(after_state, "ships") |> Map.values()

    seen = %{
      seen
      | berthed:
          seen.berthed or Enum.any?(fleet, &(&1["berth_granted_ms"] || &1["berth_queued_ms"]))
    }

    assert_invariants(after_state, catalogue, {seed, step, choice})
    {after_state, rng, seen}
  end

  defp assert_invariants(state, catalogue, context) do
    company = Game.get(state, "companies", "company")
    assert company["cash"] >= company["reserved"], inspect(context)
    assert company["reserved"] >= 0, inspect(context)
    fleet = TijaraTides.Domain.ReadState.entities(state, "ships") |> Map.values()

    for port <- ["Jakarta", "Singapore"] do
      assert Enum.count(PortBerths.ships(state, port), &PortBerths.occupied?/1) <= 1,
             inspect(context)
    end

    for row <- fleet do
      refute row["berth_granted_ms"] && row["berth_queued_ms"], inspect(context)
      if row["status"] == "sailing", do: refute(row["berth_granted_ms"], inspect(context))
      capacity = Ship.capacity(Ship.Rows.decode(row), catalogue)
      class = Fleet.classes()[row["class"]]
      assert capacity.weight <= class["weight"], inspect(context)
      assert capacity.volume <= class["volume"], inspect(context)
      assert Enum.all?(row["cargo"], &(&1["quantity"] > 0)), inspect(context)
    end

    journal = Map.get(state, :journal, [])

    for event <- journal do
      assert Enum.sum(Enum.map(event.entries, &elem(&1, 1))) == 0, inspect(context)
    end

    inventory = Enum.sum(for event <- journal, {"inventory", amount} <- event.entries, do: amount)

    aboard =
      Enum.sum(
        for row <- fleet, batch <- row["cargo"], do: batch["quantity"] * batch["unit_cost"]
      )

    assert inventory == aboard, inspect(context)
  end
end
