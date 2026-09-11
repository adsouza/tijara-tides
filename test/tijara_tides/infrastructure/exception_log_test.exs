defmodule TijaraTides.Infrastructure.ExceptionLogTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Infrastructure.ExceptionLog

  test "includes actionable message and stack location without argument values" do
    output =
      ExceptionLog.format(
        "Persistence failed",
        ArgumentError.exception("Unsupported entity kinds: [routes]"),
        [{__MODULE__, :probe, ["private-payload"], [file: ~c"probe.ex", line: 12]}]
      )

    assert output =~ "Unsupported entity kinds: [routes]"
    assert output =~ "probe.ex:12"
    refute output =~ "private-payload"
  end

  test "redacts credentials and database row details without losing the diagnosis" do
    output =
      ExceptionLog.format(
        "Failed",
        RuntimeError.exception(
          "Connection refused postgres://user:pass@host/db token=private-token api_key=private-key user@example.com\nDETAIL: private row contents"
        ),
        []
      )

    assert output =~ "Connection refused"

    for value <- [
          "user:pass",
          "private-token",
          "private-key",
          "user@example.com",
          "private row contents"
        ],
        do: refute(output =~ value)
  end

  # Postgrex appends detail as an unlabelled trailing paragraph, never as "DETAIL:", and
  # a repo query often carries no statement at all, leaving that paragraph unanchored.
  for {label, query} <- [
        {"without a statement", nil},
        {"with a statement", "INSERT INTO game_accounts (id) VALUES ($1)"}
      ] do
    test "a database violation #{label} keeps its diagnosis without the failing row" do
      error = %Postgrex.Error{
        query: unquote(query),
        postgres: %{
          severity: "ERROR",
          pg_code: "23505",
          code: :unique_violation,
          message: ~s(duplicate key value violates unique constraint "game_accounts_pkey"),
          table: "game_accounts",
          constraint: "game_accounts_pkey",
          detail: "Key (id)=(private-account) already exists."
        }
      }

      output = ExceptionLog.format("Persistence failed", error, [])

      assert output =~ "unique_violation"
      assert output =~ "game_accounts_pkey"
      refute output =~ "private-account"
      refute output =~ "INSERT INTO"
    end
  end

  test "redacts inspected credential maps" do
    output =
      ExceptionLog.format(
        "Failed",
        RuntimeError.exception(~s(%{"token" => "private-value", "password": "hidden-value"})),
        []
      )

    refute output =~ "private-value"
    refute output =~ "hidden-value"
  end

  test "pattern mismatch retains the explanation without inspecting the payload" do
    output = ExceptionLog.format("Poll failed", %CaseClauseError{term: "private-payload"}, [])
    assert output =~ "no case clause matching"
    refute output =~ "private-payload"
  end
end
