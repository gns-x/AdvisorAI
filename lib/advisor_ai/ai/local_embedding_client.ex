defmodule AdvisorAi.AI.LocalEmbeddingClient do
  @moduledoc """
  Client for generating embeddings using the local embedding server.
  """

  @local_embedding_url "http://localhost:8001"
  
  @doc """
  Generate embeddings using the local embedding server.
  """
  def embeddings(opts) do
    input = Keyword.get(opts, :input, "")

    if input == "" do
      {:error, "Input text cannot be empty"}
    else
      # Build request body
      request_body = %{
        input: input
      }

      # Make request to local embedding server
      case HTTPoison.post(
             "#{@local_embedding_url}/v1/embeddings",
             Jason.encode!(request_body),
             [
               {"Content-Type", "application/json"}
             ],
             recv_timeout: 15_000
           ) do
        {:ok, %{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, response} ->
              # Extract embedding from response
              case response do
                %{"data" => [%{"embedding" => embedding} | _]} ->
                  {:ok, %{"data" => [%{"embedding" => embedding}]}}

                _ ->
                  {:error, "Unexpected response format from local embedding server"}
              end

            {:error, reason} ->
              {:error, "Failed to parse response: #{reason}"}
          end

        {:ok, %{status_code: code, body: body}} ->
          {:error, "Local embedding server error: #{code} - #{body}"}

        {:error, reason} ->
          {:error, "Local embedding server request failed: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Check if the local embedding server is available.
  """
  def health_check do
    case HTTPoison.get("#{@local_embedding_url}/health", [], recv_timeout: 5_000) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"status" => "healthy", "model" => model}} ->
            {:ok, "Local embedding server is available using model: #{model}"}

          _ ->
            {:error, "Local embedding server returned unexpected response"}
        end

      {:ok, %{status_code: code}} ->
        {:error, "Local embedding server returned status #{code}"}

      {:error, reason} ->
        {:error, "Local embedding server health check failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Test embedding generation with a simple text.
  """
  def test_embedding do
    case embeddings(input: "test embedding") do
      {:ok, %{"data" => [%{"embedding" => embedding}]}} ->
        {:ok, "Embedding generated successfully with #{length(embedding)} dimensions"}

      {:error, reason} ->
        {:error, "Embedding test failed: #{reason}"}
    end
  end
end
