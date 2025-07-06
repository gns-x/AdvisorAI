defmodule AdvisorAi.MixProject do
  use Mix.Project

  def project do
    [
      app: :advisor_ai,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {AdvisorAi.Application, []},
      extra_applications: [:logger, :runtime_tools]
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
      {:phoenix, "~> 1.7.21"},
      {:phoenix_ecto, "~> 4.6.5"},
      {:ecto, "~> 3.9"},
      {:ecto_sql, "~> 3.9"},
      {:postgrex, "~> 0.17.5"},
      {:phoenix_html, "~> 4.1"},
      # keep your existing version
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:phoenix_live_view, "~> 1.0"},
      {:floki, ">= 0.36.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.4"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      # {:heroicons, "~> 0.5"},
      {:swoosh, "~> 1.16"},
      {:finch, "~> 0.18"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.1"},
      {:gettext, "~> 0.24"},
      {:jason, "~> 1.4"},
      {:dns_cluster, "~> 0.1.3"},
      {:bandit, "~> 1.5"},

      # Authentication / API
      {:ueberauth, "~> 0.10"},
      {:ueberauth_google, "~> 0.12"},
      {:tesla, "~> 1.9"},
      {:hackney, "~> 1.20"},

      # HTTP client for API calls
      {:httpoison, "~> 2.0"},
      {:oauth2, "~> 2.0"},

      # OpenAI integration
      {:openai, "~> 0.5"},

      # Background jobs & AWS
      {:oban, "~> 2.17"},
      {:ex_aws, "~> 2.5"},
      {:ex_aws_s3, "~> 2.5"},

      # Vectors & Requests
      {:pgvector, "~> 0.2.1"},
      {:req, "~> 0.5"},
      {:cors_plug, "~> 3.0"},

      # Testing/misc
      {:ex_machina, "~> 2.8", only: :test},
      {:mox, "~> 1.1", only: :test},
      {:uuid, "~> 1.1"},
      {:timex, "~> 3.7"},
      {:decorator, "~> 1.4"},
      {:prom_ex, "~> 1.9"},

      # Dev/test tools
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:dotenvy, "~> 0.9.0"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind advisor_ai", "esbuild advisor_ai"],
      "assets.deploy": [
        "tailwind advisor_ai --minify",
        "esbuild advisor_ai --minify",
        "phx.digest"
      ]
    ]
  end
end
