# Runs in the isolated, checksum-pinned Muex tool project, never the application.
[output | sources] = System.argv()
operators = [Muex.Mutator.Comparison, Muex.Mutator.Boolean, Muex.Mutator.Arithmetic]

records =
  Enum.flat_map(sources, fn source ->
    {:ok, [file]} = Muex.Loader.load(source, Muex.Language.Elixir)
    {:ok, canonical} = Muex.Language.Elixir.unparse(file.ast)

    Muex.Mutator.walk(file.ast, operators, %{file: source, skip_calls: []})
    |> Enum.filter(&(&1.location.line > 0))
    |> Enum.take(20)
    |> Enum.map(fn mutation ->
      {:ok, mutated} = Muex.Compiler.compile_to_source(mutation, file, Muex.Language.Elixir)

      %{
        source: source,
        line: mutation.location.line,
        operator: inspect(mutation.mutator),
        description: mutation.description,
        snippet: Muex.Reporter.Patch.of(mutation),
        canonical: canonical <> "\n",
        mutated: mutated <> "\n"
      }
    end)
  end)

File.write!(output, Jason.encode_to_iodata!(records, pretty: true))
