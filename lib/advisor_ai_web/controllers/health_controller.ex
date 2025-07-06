defmodule AdvisorAiWeb.HealthController do
  use AdvisorAiWeb, :controller

  def check(conn, _params) do
    # Check database connection
    db_status = check_database()

    # Check OpenAI connection
    openai_status = check_openai()

    # Check OpenRouter connection
    openrouter_status = check_openrouter()

    status = %{
      status: "healthy",
      timestamp: DateTime.utc_now(),
      services: %{
        database: db_status,
        openai: openai_status,
        openrouter: openrouter_status
      }
    }

    conn
    |> put_status(:ok)
    |> json(status)
  end

  defp check_database do
    try do
      case AdvisorAi.Repo.query("SELECT 1") do
        {:ok, _} -> %{status: "healthy", message: "Database connection successful"}
        {:error, reason} -> %{status: "unhealthy", message: "Database connection failed: #{inspect(reason)}"}
      end
    rescue
      e -> %{status: "unhealthy", message: "Database check failed: #{inspect(e)}"}
    end
  end

  defp check_openai do
    try do
      case OpenAI.models() do
        {:ok, _} -> %{status: "healthy", message: "OpenAI connection successful"}
        {:error, reason} -> %{status: "unhealthy", message: "OpenAI connection failed: #{inspect(reason)}"}
      end
    rescue
      e -> %{status: "unhealthy", message: "OpenAI check failed: #{inspect(e)}"}
    end
  end

  defp check_openrouter do
    try do
      case AdvisorAi.AI.OpenRouterClient.health_check() do
        {:ok, _} -> %{status: "healthy", message: "OpenRouter connection successful"}
        {:error, reason} -> %{status: "unhealthy", message: "OpenRouter connection failed: #{inspect(reason)}"}
      end
    rescue
      e -> %{status: "unhealthy", message: "OpenRouter check failed: #{inspect(e)}"}
    end
  end
end
