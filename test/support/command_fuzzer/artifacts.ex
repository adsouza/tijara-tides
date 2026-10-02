defmodule TijaraTides.CommandFuzzer.Artifacts do
  @moduledoc "Versioned, credential-free replay records saved before a failure reaches the shrinker."
  @version 1

  def version, do: @version

  def failure(r, action, error, stack) do
    root = root(r)
    File.mkdir_p!(root)

    record =
      record(r)
      |> Map.merge(%{
        failing_action: action,
        invariant: Exception.message(error),
        stack: Exception.format_stacktrace(stack)
      })

    original = Path.join(root, "original.json")
    unless File.exists?(original), do: write(original, record)
    write(Path.join(root, "minimized.json"), record)
    File.write!(Path.join(root, "replay.etf"), :erlang.term_to_binary(replay_record(r)))
    IO.puts(:stderr, "Fuzzer failure saved to #{root}: #{Exception.message(error)}")
  end

  def success(r) do
    if System.get_env("TIJARA_FUZZ_CORPUS") do
      root = "cover/command-fuzzer-corpus"
      File.mkdir_p!(root)
      # Declared semantic interest, not inferred branch coverage. At most 50 entries.
      key =
        {r.family, Enum.map(r.trace, &{&1.symbolic.op, Map.get(&1.symbolic, :spec)}),
         Enum.sort(r.model.milestones)}

      name = Base.encode16(:crypto.hash(:sha256, :erlang.term_to_binary(key)), case: :lower)
      path = Path.join(root, name <> ".etf")

      if File.exists?(path) or length(Path.wildcard(root <> "/*.etf")) < 50,
        do: File.write!(path, :erlang.term_to_binary(replay_record(r)))
    end

    :ok
  end

  def read!(path) do
    record = path |> File.read!() |> :erlang.binary_to_term([:safe])
    if record.version != @version, do: raise(ArgumentError, "Incompatible fuzzer corpus version")
    record
  end

  defp replay_record(r),
    do: %{
      version: @version,
      family: r.family,
      parameters: r.parameters,
      suffix: r.suffix,
      seed: ExUnit.configuration()[:seed],
      valuation_seed: "fuzzer-valuation-v1"
    }

  defp record(r),
    do:
      Map.merge(replay_record(r), %{
        backend: r.backend.kind,
        revision: revision(),
        stats: r.stats,
        trace: r.trace,
        milestones: Enum.sort(r.model.milestones),
        clock_ms: r.game.clock_ms,
        fixture: "two-owner-established-v1; weather chance=0"
      })

  defp root(r),
    do: Path.join(["cover/property-failures", to_string(r.family), to_string(r.artifact)])

  defp revision do
    case System.cmd("git", ["rev-parse", "HEAD"], stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      _ -> "unavailable"
    end
  end

  defp write(path, record),
    do: File.write!(path, Jason.encode_to_iodata!(safe(record), pretty: true))

  defp safe(%MapSet{} = value), do: value |> Enum.sort() |> safe()

  defp safe(value) when is_map(value),
    do: Map.new(value, fn {k, v} -> {to_string(k), safe(v)} end)

  defp safe(value) when is_tuple(value), do: value |> Tuple.to_list() |> safe()
  defp safe(value) when is_list(value), do: Enum.map(value, &safe/1)

  defp safe(value) when is_binary(value) do
    if String.valid?(value), do: value, else: %{invalid_utf8_hex: Base.encode16(value)}
  end

  defp safe(value) when is_atom(value), do: value
  defp safe(value), do: value
end
