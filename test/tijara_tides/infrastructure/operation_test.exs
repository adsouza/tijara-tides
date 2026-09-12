defmodule TijaraTides.Infrastructure.OperationTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  alias TijaraTides.Infrastructure.{Operation, OperationLogger}

  setup do
    id = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach_many(
        id,
        for(event <- [:start, :stop, :exception], do: [:tijara_tides, :operation, event]),
        &__MODULE__.event/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(id) end)
    :ok
  end

  def event(event, measurements, metadata, owner) do
    if self() == owner, do: send(owner, {event, measurements, metadata})
  end

  test "returns results unchanged, times operations, and scopes correlation metadata" do
    Logger.metadata(correlation_id: "outer")
    result = {:ok, %{token: "must-not-appear"}}

    assert Operation.run(:command, fn ->
             refute Logger.metadata()[:correlation_id] == "outer"
             result
           end) == result

    assert Logger.metadata()[:correlation_id] == "outer"
    assert_receive {[:tijara_tides, :operation, :start], %{system_time: _}, start}
    assert_receive {[:tijara_tides, :operation, :stop], %{duration: duration}, stop}
    assert duration >= 0
    assert start.correlation_id == stop.correlation_id
    assert byte_size(stop.correlation_id) == 32
    assert stop.outcome == :ok
    refute inspect(stop) =~ "must-not-appear"
  end

  test "outcomes expose no return payloads" do
    for {result, expected} <- [
          {{:ok, %{committed?: false}}, :replay},
          {{:error, %{token: "private"}}, :error},
          {{:halt, :ownership_lost}, :halted},
          {{:reply, {:error, :invalid_session}, %{status: :ready}}, :error},
          {{:reply, {:error, :storage_unavailable}, %{status: :unavailable}}, :halted},
          {{:noreply, %{status: :unavailable}}, :halted}
        ] do
      capture_log(fn -> assert Operation.run(:command, fn -> result end) == result end)
      assert_receive {[:tijara_tides, :operation, :stop], _, metadata}
      assert metadata.outcome == expected
      refute inspect(metadata) =~ "private"
    end
  end

  test "exceptions retain messages and stacks, redact credentials, and are re-raised" do
    log =
      capture_log(fn ->
        assert_raise RuntimeError, "failed api_key=super-secret", fn ->
          Operation.run(:command, fn -> raise "failed api_key=super-secret" end)
        end
      end)

    assert_receive {[:tijara_tides, :operation, :exception], %{duration: duration}, metadata}
    assert duration >= 0
    assert metadata.kind == :error
    assert metadata.diagnostic =~ "RuntimeError: failed"
    assert metadata.diagnostic =~ "operation_test.exs"
    refute inspect(metadata) =~ "super-secret"
    refute log =~ "super-secret"
    assert log =~ "outcome=exception"
    assert log =~ "correlation_id=#{metadata.correlation_id}"
  end

  test "exits and throws are preserved without publishing their payloads" do
    capture_log(fn ->
      assert catch_exit(Operation.run(:email_delivery, fn -> exit({:private, "credential"}) end)) ==
               {:private, "credential"}

      assert catch_throw(Operation.run(:command, fn -> throw("credential") end)) == "credential"
    end)

    for kind <- [:exit, :throw] do
      assert_receive {[:tijara_tides, :operation, :exception], _, metadata}
      assert metadata.kind == kind
      refute inspect(metadata) =~ "credential"
    end
  end

  test "returned exceptions use the same redaction and attachment is idempotent" do
    assert :ok = OperationLogger.attach()
    assert :ok = OperationLogger.attach()
    error = RuntimeError.exception("failed api_key=super-secret")

    log =
      capture_log(fn ->
        assert Operation.run(:email_delivery, fn -> {:error, error} end) == {:error, error}
      end)

    assert_receive {[:tijara_tides, :operation, :stop], _, metadata}
    assert metadata.outcome == :error
    refute inspect(metadata) =~ "super-secret"
    assert length(Regex.scan(~r/operation=email_delivery/, log)) == 1
  end
end
