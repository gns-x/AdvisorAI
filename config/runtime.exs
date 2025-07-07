import Config

# Development environment - load .env file
if config_env() == :dev && File.exists?(".env") do
  File.read!(".env")
  |> String.split("\n")
  |> Enum.reject(&(&1 == "" || String.starts_with?(&1, "#")))
  |> Enum.each(fn line ->
    case String.split(line, "=", parts: 2) do
      [key, value] -> System.put_env(String.trim(key), String.trim(value))
      _ -> nil
    end
  end)
end

# Configure OAuth for both dev and prod
if config_env() in [:dev, :prod] do
  config :ueberauth, Ueberauth.Strategy.Google.OAuth,
    client_id: System.get_env("GOOGLE_CLIENT_ID"),
    client_secret: System.get_env("GOOGLE_CLIENT_SECRET")

  # OpenAI Config
  config :openai,
    api_key: System.get_env("OPENAI_API_KEY"),
    organization_key: System.get_env("OPENAI_ORG_KEY"),
    http_options: [
      timeout: 60_000,
      recv_timeout: 60_000
    ]

  # Default model configuration
  config :advisor_ai, :openai, default_model: System.get_env("OPENAI_MODEL") || "gpt-3.5-turbo"

  # HubSpot Config
  config :advisor_ai, :hubspot,
    client_id: System.get_env("HUBSPOT_CLIENT_ID"),
    client_secret: System.get_env("HUBSPOT_CLIENT_SECRET"),
    redirect_uri: System.get_env("HUBSPOT_REDIRECT_URI")

  # Oban configuration
  config :advisor_ai, Oban,
    repo: AdvisorAi.Repo,
    plugins: [Oban.Plugins.Pruner],
    queues: [default: 10, mailers: 10, ai_processing: 5]

  config :advisor_ai, :embedding_client,
    embedding_url: "https://openrouter.ai/api/v1/embeddings",
    api_key: System.get_env("OPENROUTER_API_KEY")

  config :advisor_ai, :ollama_client,
    ollama_url: "https://openrouter.ai/api/v1",
    api_key: System.get_env("OPENROUTER_API_KEY")

  config :advisor_ai, :google_project_id, "advisor-465014"
end

# Production specific config
if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  config :advisor_ai, AdvisorAi.Repo,
    ssl: true,
    ssl_opts: [verify: :verify_none],
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: if(System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []),
    prepare: :unnamed

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  config :advisor_ai, AdvisorAiWeb.Endpoint,
    url: [host: System.get_env("PHX_HOST") || "example.com", port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: String.to_integer(System.get_env("PORT") || "4000")
    ],
    secret_key_base: secret_key_base,
    server: true

  # Oban configuration for production
  config :advisor_ai, Oban,
    repo: AdvisorAi.Repo,
    plugins: [Oban.Plugins.Pruner],
    queues: [default: 10, mailers: 10, ai_processing: 5]
end
