defmodule AdvisorAi.AI.OllamaClient do
  @moduledoc """
  Client for interacting with Ollama local AI models.
  """

  @ollama_url "http://localhost:11434"

  @doc """
  Generate a chat completion using Ollama.
  """
  def chat_completion(opts) do
    model = Keyword.get(opts, :model, "llama3.2:3b")
    messages = Keyword.get(opts, :messages, [])
    temperature = Keyword.get(opts, :temperature, 0.7)
    max_tokens = Keyword.get(opts, :max_tokens, 1000)

    # Convert messages to Ollama format
    prompt = build_prompt(messages)

    request_body = %{
      model: model,
      prompt: prompt,
      stream: false,
      options: %{
        temperature: temperature,
        num_predict: max_tokens
      }
    }

    case HTTPoison.post("#{@ollama_url}/api/generate", Jason.encode!(request_body), [
      {"Content-Type", "application/json"}
    ]) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"response" => response}} ->
            {:ok, %{choices: [%{message: %{content: response}}]}}
          {:error, reason} ->
            {:error, "Failed to parse Ollama response: #{inspect(reason)}"}
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        {:error, "Ollama API error: #{status_code} - #{body}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "HTTP error: #{inspect(reason)}"}
    end
  end

  @doc """
  Generate embeddings using Ollama.
  """
  def embeddings(opts) do
    model = Keyword.get(opts, :model, "llama3.2:3b")
    input = Keyword.get(opts, :input, "")

    request_body = %{
      model: model,
      prompt: input
    }

    case HTTPoison.post("#{@ollama_url}/api/embeddings", Jason.encode!(request_body), [
      {"Content-Type", "application/json"}
    ]) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"embedding" => embedding}} ->
            {:ok, %{data: [%{embedding: embedding}]}}
          {:error, reason} ->
            {:error, "Failed to parse Ollama embeddings response: #{inspect(reason)}"}
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        {:error, "Ollama embeddings API error: #{status_code} - #{body}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "HTTP error: #{inspect(reason)}"}
    end
  end

  @doc """
  Check if Ollama is running and accessible.
  """
  def health_check do
    case HTTPoison.get("#{@ollama_url}/api/tags") do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        {:ok, "Ollama is running"}
      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, "Ollama health check failed: #{status_code}"}
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Ollama is not running: #{inspect(reason)}"}
    end
  end

  # Private functions

  defp build_prompt(messages) do
    messages
    |> Enum.map(fn
      %{role: "system", content: content} ->
        "System: #{content}\n"
      %{role: "user", content: content} ->
        "User: #{content}\n"
      %{role: "assistant", content: content} ->
        "Assistant: #{content}\n"
    end)
    |> Enum.join("")
    |> Kernel.<>("Assistant: ")
  end
end
