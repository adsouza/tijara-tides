excluded = if System.get_env("TIJARA_TEST_DB_PORT"), do: [], else: [:game_database]

excluded =
  if System.get_env("TIJARA_BROWSER_TEST_PORT"), do: excluded, else: [:browser | excluded]

ExUnit.start(exclude: excluded)

# Ecto accepts version/module pairs. Load each file once, then reuse its module
# across isolated schemas instead of recompiling it on every migration run.
defmodule TijaraTides.TestMigrations do
  @migrations Application.app_dir(:tijara_tides, "priv/repo/migrations")
              |> Path.join("*.exs")
              |> Path.wildcard()
              |> Enum.sort()
              |> Enum.map(fn path ->
                {version, _} = path |> Path.basename() |> Integer.parse()
                [{module, _}] = Code.require_file(path)
                {version, module}
              end)

  def all, do: @migrations
end
