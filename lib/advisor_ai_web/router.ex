defmodule AdvisorAiWeb.Router do
  use AdvisorAiWeb, :router

  import AdvisorAiWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AdvisorAiWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Public routes
  scope "/", AdvisorAiWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/", PageController, :home
  end

  # Authentication routes
  scope "/auth", AdvisorAiWeb do
    pipe_through [:browser]

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
  end

  # Protected routes
  scope "/", AdvisorAiWeb do
    pipe_through [:browser, :require_authenticated_user]

    live "/chat", ChatLive.Index, :index
    live "/chat/:id", ChatLive.Show, :show

    delete "/auth/logout", AuthController, :delete

    # Settings routes
    live "/settings", SettingsLive.Index, :index
    live "/settings/integrations", SettingsLive.Integrations, :index
    live "/settings/instructions", SettingsLive.Instructions, :index
  end

  # API routes (for webhooks and integrations)
  scope "/api", AdvisorAiWeb do
    pipe_through :api

    post "/webhooks/gmail", WebhookController, :gmail
    post "/webhooks/calendar", WebhookController, :calendar
    post "/webhooks/hubspot", WebhookController, :hubspot
    post "/test/email-automation", WebhookController, :test_email_automation
    post "/test/hubspot-contact-creation", WebhookController, :test_hubspot_contact_creation
    post "/process-email", WebhookController, :process_manual_email
  end

  # Health check endpoint
  scope "/", AdvisorAiWeb do
    pipe_through :api

    get "/health", HealthController, :check
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:advisor_ai, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AdvisorAiWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  scope "/hubspot/oauth", AdvisorAiWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/connect", HubspotOauthController, :connect
    get "/callback", HubspotOauthController, :callback
    get "/debug", HubspotOauthController, :debug
    get "/test", HubspotOauthController, :test_app
    get "/test-api-key", HubspotOauthController, :test_api_key
    get "/help", HubspotOauthController, :help
  end
end
