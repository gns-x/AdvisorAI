defmodule AdvisorAi.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Configure Postgrex types for pgvector
    Postgrex.Types.define(
      Pgvector.PostgresTypes,
      [Pgvector.Extensions.Vector],
      []
    )

    children = [
      AdvisorAiWeb.Telemetry,
      AdvisorAi.Repo,
      {DNSCluster, query: Application.get_env(:advisor_ai, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: AdvisorAi.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: AdvisorAi.Finch},
      # Start Oban for background jobs
      {Oban, Application.fetch_env!(:advisor_ai, Oban)},
      # Start a worker by calling: AdvisorAi.Worker.start_link(arg)
      # {AdvisorAi.Worker, arg},
      # Start to serve requests, typically the last entry
      AdvisorAiWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AdvisorAi.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        # Schedule token monitoring
        schedule_token_monitoring()
        {:ok, pid}

      error ->
        error
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AdvisorAiWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp schedule_token_monitoring do
    # Schedule token monitoring for all environments
    AdvisorAi.Workers.TokenMonitorWorker.schedule_token_monitoring()
  end
end
