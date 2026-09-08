defmodule Docs.ArchitectureTest do
  use ExUnit.Case, async: true

  test "README entry point links the canonical architecture and resolves its diagram modules" do
    readme = File.read!("README.md")
    overview = File.read!("ARCHITECTURE.md")
    assert readme =~ "ARCHITECTURE.md"
    assert overview =~ "](docs/architecture.md)"
    assert File.exists?("docs/architecture.md")
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
