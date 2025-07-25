defmodule AdvisorAiWeb.HealthController do
  use AdvisorAiWeb, :controller

  def check(conn, _params) do
    # Check database connection
    db_status = check_database()

    # Check OpenAI connection
    openai_status = check_openai()

    # Check Groq connection
    groq_status = check_groq()

    status = %{
      status: "healthy",
      timestamp: DateTime.utc_now(),
      services: %{
        database: db_status,
        openai: openai_status,
        groq: groq_status
      }
    }

    conn
    |> put_status(:ok)
    |> json(status)
  end

  defp check_database do
    try do
      case AdvisorAi.Repo.query("SELECT 1") do
        {:ok, _} ->
          %{status: "healthy", message: "Database connection successful"}

        {:error, reason} ->
          %{status: "unhealthy", message: "Database connection failed: #{inspect(reason)}"}
      end
    rescue
      e -> %{status: "unhealthy", message: "Database check failed: #{inspect(e)}"}
    end
  end

  defp check_openai do
    try do
      case OpenAI.models() do
        {:ok, _} ->
          %{status: "healthy", message: "OpenAI connection successful"}

        {:error, reason} ->
          %{status: "unhealthy", message: "OpenAI connection failed: #{inspect(reason)}"}
      end
    rescue
      e -> %{status: "unhealthy", message: "OpenAI check failed: #{inspect(e)}"}
    end
  end

  defp check_groq do
    try do
      case AdvisorAi.AI.GroqClient.health_check() do
        {:ok, message} ->
          %{status: "healthy", message: message}

        {:error, reason} ->
          %{status: "unhealthy", message: "Groq connection failed: #{inspect(reason)}"}
      end
    rescue
      e -> %{status: "unhealthy", message: "Groq check failed: #{inspect(e)}"}
    end
  end

  def embedding_models(conn, _params) do
    case AdvisorAi.AI.GroqClient.list_models() do
      {:ok, models} ->
        # Filter for embedding models
        embedding_models =
          Enum.filter(models, fn model ->
            model["object"] == "model" and
              String.contains?(model["id"] || "", "embed")
          end)

        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          models: embedding_models,
          count: length(embedding_models)
        })

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          status: "error",
          message: "Failed to get embedding models",
          error: reason
        })
    end
  end
end
