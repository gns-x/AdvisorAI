import Config

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL")

  config :advisor_ai, AdvisorAi.Repo,
    ssl: true,
    ssl_opts: [verify: :verify_none],
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: if(System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: [])

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
    secret_key_base: secret_key_base

  # Google OAuth Config
  config :ueberauth, Ueberauth.Strategy.Google.OAuth,
    client_id: System.get_env("GOOGLE_CLIENT_ID"),
    client_secret: System.get_env("GOOGLE_CLIENT_SECRET")

  # OpenAI Config
  config :advisor_ai, :openai,
    api_key: System.get_env("OPENAI_API_KEY"),
    model: System.get_env("OPENAI_MODEL") || "gpt-4-turbo-preview"

  # HubSpot Config
  config :advisor_ai, :hubspot,
    client_id: System.get_env("HUBSPOT_CLIENT_ID"),
    client_secret: System.get_env("HUBSPOT_CLIENT_SECRET"),
    redirect_uri: System.get_env("HUBSPOT_REDIRECT_URI")
end
