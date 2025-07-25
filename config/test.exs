import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :advisor_ai, AdvisorAi.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "advisor_ai_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :advisor_ai, AdvisorAiWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "eGG2keV9aonHTDZ9co8SLvWqtUQ+U1My3ZlK5SXDkd48dmlFJ5ag0hv2rvdw82P2",
  server: false

# Disable live reload in test
config :advisor_ai, :dev_routes, false

# In test we don't send emails
config :advisor_ai, AdvisorAi.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :advisor_ai, Oban,
  repo: AdvisorAi.Repo,
  queues: [default: 10, mailers: 10, ai_processing: 5],
  plugins: false

# Configure Mox for mocking
config :advisor_ai,
  gmail_module: AdvisorAi.Integrations.Gmail,
  calendar_module: AdvisorAi.Integrations.Calendar,
  accounts_module: AdvisorAi.Accounts
