defmodule TijaraTides.UseCases.FuzzerContractTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias TijaraTides.CommandFuzzer, as: F
  alias TijaraTides.CommandFuzzer.{Artifacts, Runner, Scenarios, Specs}
  @p %{quantity: 1, amount: 100, mode: 0}

  test "removed symbolic creator makes only the dependent action skip" do
    r = Runner.pure(:broad, @p, [Scenarios.command(:preset_delete)])
    assert r.stats.skipped == 1
    assert r.stats.accepted == 5
    assert List.last(r.trace).outcome == :skipped
    refute Specs.eligible?(Scenarios.command(:repay), %{loan: nil})
  end

  test "a rescued command_failed is archived and propagates as a finding" do
    dir = "cover/property-failures/berths/rescued-error"
    File.rm_rf!(dir)

    callback = fn game, cat, _actor, payload, _id ->
      F.run(game, put_in(cat, ["goods", "lumber", "id"], "grain"), payload)
    end

    capture_io(:stderr, fn ->
      assert_raise ExUnit.AssertionError, ~r/Unexpected command outcome.*command_failed/s, fn ->
        Runner.pure(:berths, @p, [], artifact: "rescued-error", backend: %{command: callback})
      end
    end)

    record = Jason.decode!(File.read!(dir <> "/minimized.json"))
    assert record["invariant"] =~ "command_failed"
    assert record["stats"]["attempted"] == 1

    assert record["trace"] |> List.last() |> Map.fetch!("resolved") |> Map.fetch!("action") ==
             "buy"

    assert Artifacts.read!(dir <> "/replay.etf").suffix == []
  end

  test "sequence sensitivity shrinks to creator plus consumer and replays the same invariant" do
    callback = fn game, cat, _actor, payload, id ->
      if payload["action"] == "markdown_preset_delete" and
           game.entities["markdown_presets"][payload["preset"]]["name"] == "Shrink trigger" do
        {:ok, game, %{}}
      else
        F.execute(game, cat, payload, id)
      end
    end

    fixture =
      Jason.decode!(
        File.read!("test/fixtures/property_regressions/command_fuzzer/preset-lifetime.json")
      )

    assert fixture["actions"] == ["preset_save", "preset_delete"]
    save = Scenarios.command(:preset_save, %{"name" => "Shrink trigger"}, as: :preset)
    delete = Scenarios.command(:preset_delete)

    noise =
      StreamData.list_of(StreamData.constant(Scenarios.command(:locale, %{"locale" => "en"})),
        max_length: 8
      )

    generator = StreamData.tuple({noise, noise, noise})

    result =
      capture_io(:stderr, fn ->
        assert {:error, metadata} =
                 StreamData.check_all(
                   generator,
                   [
                     initial_seed: {12345, 22, 33},
                     initial_size: 20,
                     max_runs: 20,
                     max_shrinking_steps: 100
                   ],
                   fn {a, b, c} ->
                     suffix = a ++ [save] ++ b ++ [delete] ++ c

                     try do
                       Runner.pure(:broad, @p, suffix,
                         limit: 60,
                         artifact: "sequence-sensitivity",
                         backend: %{command: callback}
                       )

                       {:ok, nil}
                     rescue
                       error in ExUnit.AssertionError -> {:error, {suffix, error.message}}
                     end
                   end
                 )

        {suffix, message} = metadata.shrunk_failure
        assert suffix == [save, delete]
        assert message =~ "preset lifetime"

        assert_raise ExUnit.AssertionError, fn ->
          Runner.pure(:broad, @p, suffix,
            artifact: "sequence-sensitivity",
            backend: %{command: callback}
          )
        end

        # The saved minimal counterexample passes with the production behavior restored.
        assert Runner.pure(:broad, @p, suffix).stats.accepted == 7
      end)

    assert result =~ "Fuzzer failure saved"
  end

  test "unbacked reservation fails the independent conservation oracle" do
    callback = fn game, cat, _actor, payload, id ->
      {:ok, game, reply} = F.execute(game, cat, payload, id)
      game = update_in(game, [:entities, "companies", "company", "reserved"], &(&1 + 1))
      {:ok, game, reply}
    end

    capture_io(:stderr, fn ->
      assert_raise ExUnit.AssertionError, ~r/reservation conservation/, fn ->
        Runner.pure(:broad, @p, [],
          artifact: "reservation-sensitivity",
          backend: %{command: callback}
        )
      end
    end)
  end

  test "payload sensitivity shrinks to NUL and historical regression is accepted as a rejection" do
    generator = StreamData.string(:alphanumeric, max_length: 20)

    assert {:error, metadata} =
             StreamData.check_all(
               generator,
               [
                 initial_seed: {12345, 44, 55},
                 initial_size: 20,
                 max_runs: 20,
                 max_shrinking_steps: 100
               ],
               fn prefix ->
                 {game, cat} = F.fixture()
                 name = prefix <> <<0>>
                 payload = F.Contracts.name_command(:ship, name)

                 # A planted permissive-input mutant: forwarding this reply violates the rejection contract.
                 result = F.execute(game, cat, Map.put(payload, "name", "Safe"))

                 case result do
                   {:ok, _, _} -> {:error, name}
                   other -> flunk("Fault setup did not reach admission: #{inspect(other)}")
                 end
               end
             )

    assert metadata.shrunk_failure == <<0>>

    fixture =
      Jason.decode!(
        File.read!("test/fixtures/property_regressions/command_fuzzer/unsafe-name.json")
      )

    {game, cat} = F.fixture()

    assert {:error, :ship_name_invalid} =
             F.execute(game, cat, F.Contracts.name_command(:ship, fixture["name"]))

    assert Specs.eligible?(Scenarios.command(:foreign_ship, %{}, error: :ship_not_owned), %{
             active: true
           })
  end
end
