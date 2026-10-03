defmodule TijaraTides.UseCases.CommandPayloadPropertiesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias TijaraTides.CommandFuzzer, as: Fuzzer
  alias TijaraTides.CommandFuzzer.Contracts
  alias TijaraTides.Domain.{Game, ReadState}

  test "name table covers accepted boundaries and safely rejected values in three commands" do
    for kind <- [:company, :ship, :preset],
        {name, expected} <- Contracts.names(Contracts.limit(kind)) do
      check_name(kind, name, expected)
    end
  end

  property "forbidden name characters reject without committing and a corrected request succeeds" do
    check all(
            kind <- member_of([:company, :ship, :preset]),
            char <- member_of(Contracts.forbidden()),
            prefix <- string(:alphanumeric, max_length: 10),
            max_runs: 50,
            max_shrinking_steps: 100
          ) do
      check_name(kind, prefix <> "a" <> <<char::utf8>> <> "b", :error)
    end
  end

  property "combining marks count independently of bytes and control-free name limits" do
    check all(
            kind <- member_of([:company, :ship, :preset]),
            # One grapheme each, spanning one, two or three code points.
            unit <- member_of(["a", "e\u0301", "e\u0301\u0323"]),
            count <- integer(1..81),
            max_runs: 50,
            max_shrinking_steps: 100
          ) do
      name = String.duplicate(unit, count)
      # Graphemes are capped per kind; every stored name also fits the SQL code-point cap.
      expected = if Contracts.name_accepted?(kind, name), do: :ok, else: :error
      check_name(kind, name, expected)
    end
  end

  property "preset client references cannot create identities or edit foreign identities" do
    check all(
            reference <- member_of(Contracts.references()),
            max_runs: 50,
            max_shrinking_steps: 100
          ) do
      {game, catalogue} = Fuzzer.fixture()
      {:ok, game, _} = Game.seed_invite(game, "other-invite")

      {:ok, game, _} =
        Game.redeem(game, "other-invite", "other-session", %{id: "other", wall_ms: 0})

      {:ok, game, _} =
        TijaraTides.UseCases.GameCommands.execute(
          game,
          ReadState.get(game, "accounts", "other"),
          Contracts.name_command(:preset, "Foreign"),
          %{id: "unknown", wall_ms: 1, catalogue: catalogue, auction_seed: "fixture-seed"}
        )

      payload = Contracts.name_command(:preset, "Safe") |> Map.put("preset", reference)

      assert {:error, :exchange_freshness_invalid} =
               Fuzzer.run(game, catalogue, payload,
                 commit: fn _, _, _ -> flunk("invalid identity committed") end
               )

      assert {:ok, result} = Fuzzer.run(game, catalogue, Contracts.name_command(:preset, "Safe"))
      assert result.game.entities["markdown_presets"]["allocated"]["account_id"] == "account"
    end
  end

  property "envelope mutations reject at their boundary and extra semantic fields can be admitted" do
    check all(
            variation <- member_of([:shape, :fields, :bytes, :session, :extra]),
            max_runs: 50,
            max_shrinking_steps: 100
          ) do
      {game, catalogue} = Fuzzer.fixture(false)
      valid = Contracts.name_command(:company, "Safe")

      {payload, expected, session} =
        case variation do
          :shape ->
            {[], :invalid_command_payload, "session"}

          :fields ->
            {Map.new(1..13, &{"field#{&1}", 0}), :too_many_command_fields, "session"}

          :bytes ->
            {Map.put(valid, "extra", String.duplicate("x", 4096)), :command_payload_too_large,
             "session"}

          :session ->
            {valid, :invalid_session, "wrong"}

          :extra ->
            {Map.put(valid, "extra", false), :ok, "session"}
        end

      if expected == :ok do
        assert {:ok, result} = Fuzzer.run(game, catalogue, payload)
        assert result.reply == %{"company_id" => "allocated"}
      else
        assert {:error, ^expected} =
                 Fuzzer.run(game, catalogue, payload,
                   session: session,
                   commit: fn _, _, _ -> flunk("envelope committed") end
                 )

        assert {:ok, _} = Fuzzer.run(game, catalogue, valid)
      end
    end
  end

  test "unexpected rescued planner errors and halts are findings, never allowed rejections" do
    for reply <- [{:error, :command_failed}, {:error, :internal_error}, {:halt, :ownership_lost}] do
      assert_raise ExUnit.AssertionError, fn -> Fuzzer.outcome!(reply) end
    end

    {game, catalogue} = Fuzzer.fixture()
    broken = put_in(catalogue, ["goods", "lumber", "id"], "grain")

    payload = %{
      "action" => "buy",
      "ship" => "company:1",
      "good" => "lumber",
      "quantity" => 1,
      "limit" => 1_000_000,
      "destination" => "Singapore"
    }

    ExUnit.CaptureLog.capture_log(fn ->
      assert_raise ExUnit.AssertionError, ~r/command_failed/, fn ->
        Fuzzer.run(game, broken, payload) |> Fuzzer.outcome!()
      end
    end)
  end

  test "numeric and ownership boundaries preserve cash and corrected commands remain usable" do
    {game, catalogue} = Fuzzer.fixture()

    for amount <- [nil, false, [], %{}, -1, 0, 1.5] do
      payload = %{"action" => "borrow", "amount" => amount}

      assert {:error, :loan_invalid_amount} =
               Fuzzer.run(game, catalogue, payload,
                 commit: fn _, _, _ -> flunk("invalid loan committed") end
               )
    end

    for reference <- Contracts.references() do
      assert {:error, :ship_not_owned} =
               Fuzzer.run(game, catalogue, %{
                 "action" => "rename_ship",
                 "ship" => reference,
                 "name" => "Safe"
               })
    end

    assert ReadState.get(game, "companies", "company")["reserved"] == 0

    assert {:ok, _} =
             Fuzzer.run(game, catalogue, %{
               "action" => "rename_ship",
               "ship" => "company:1",
               "name" => "Corrected"
             })
  end

  defp check_name(kind, name, expected) do
    {game, catalogue} = Fuzzer.fixture(kind != :company)
    payload = Contracts.name_command(kind, name)

    if expected == :ok do
      assert {:ok, result} = Fuzzer.run(game, catalogue, payload)

      {table, id} =
        case kind do
          :company -> {"companies", "allocated"}
          :ship -> {"ships", "company:1"}
          :preset -> {"markdown_presets", "allocated"}
        end

      assert Game.get(result.game, table, id)["name"] == String.trim(name)
    else
      error = Contracts.name_error(kind)

      assert {:error, ^error} =
               Fuzzer.run(game, catalogue, payload,
                 commit: fn _, _, _ -> flunk("unsafe name committed") end
               )

      assert {:ok, _} = Fuzzer.run(game, catalogue, Contracts.name_command(kind, "Corrected"))
    end
  end
end
