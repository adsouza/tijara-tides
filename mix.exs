defmodule TijaraTides.MixProject do
  use Mix.Project

  def project do
    [
      app: :tijara_tides,
      version: "0.1.0",
      elixir: "~> 1.19 and >= 1.19.3",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      test_coverage: [summary: [threshold: 90]],
      deps: deps(),
      compilers: [:boundary, :phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      boundary: [
        default: [
          check: [
            apps: [:phoenix, :phoenix_live_view, :phoenix_pubsub, :ecto, :ecto_sql, :postgrex]
          ]
        ]
      ],
      releases: [tijara_tides: [steps: [&deploy_assets/1, :assemble]]]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {TijaraTides.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.9"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.22"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:remote_ip, "~> 1.2"},
      {:swoosh, "~> 1.28"},
      {:gen_smtp, "~> 1.3"},
      {:boundary, "~> 0.10", runtime: false},
      {:bandit, "~> 1.5"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp deploy_assets(release) do
    Mix.Task.run("assets.deploy")
    release
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind tijara_tides", "esbuild tijara_tides"],
      "assets.deploy": [
        "tailwind tijara_tides --minify",
        "esbuild tijara_tides --minify",
        "phx.digest"
      ],
      precommit: ["format --check-formatted", "compile --force --warnings-as-errors", "test"]
    ]
  end
end
