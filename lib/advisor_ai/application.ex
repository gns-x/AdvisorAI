defmodule AdvisorAi.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AdvisorAiWeb.Telemetry,
      AdvisorAi.Repo,
      {DNSCluster, query: Application.get_env(:advisor_ai, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: AdvisorAi.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: AdvisorAi.Finch},
      # Start a worker by calling: AdvisorAi.Worker.start_link(arg)
      # {AdvisorAi.Worker, arg},
      # Start to serve requests, typically the last entry
      AdvisorAiWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AdvisorAi.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AdvisorAiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
