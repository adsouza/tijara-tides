defmodule Docs.ArchitectureTest do
  use ExUnit.Case, async: true

  test "README and the root pointer link the canonical architecture, whose diagram modules resolve" do
    readme = File.read!("README.md")
    pointer = File.read!("ARCHITECTURE.md")
    overview = File.read!("docs/architecture.md")
    assert readme =~ "](docs/architecture.md)"
    assert pointer =~ "](docs/architecture.md)"
    [_, diagram] = Regex.run(~r/```text\n(.*?)```/s, overview)
    modules = Regex.scan(~r/\b(?:Infrastructure|UseCases|Domain)\.[A-Z][\w.]*/, diagram)
    assert length(modules) > 5

    for [name] <- modules do
      assert Code.ensure_loaded?(Module.concat([TijaraTides, name])),
             "unresolved diagram module #{name}"
    end

    refute diagram =~ "→ Domain.Game"
  end
end
