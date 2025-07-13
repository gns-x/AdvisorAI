defmodule AdvisorAi.AI.GroqClient do
  @moduledoc """
  Client for interacting with Groq API (OpenAI-compatible).
  Groq provides ultra-fast LLM inference with OpenAI compatibility.
  """

  @groq_api_url "https://api.groq.com/openai/v1"

  @doc """
  Generate a chat completion using Groq.
  """
  def chat_completion(opts) do
    model = Keyword.get(opts, :model, "llama-3.3-70b-versatile")
    messages = Keyword.get(opts, :messages, [])
    functions = Keyword.get(opts, :functions, [])
    function_call = Keyword.get(opts, :function_call, nil)
    tools = Keyword.get(opts, :tools, [])
    tool_choice = Keyword.get(opts, :tool_choice, nil)
    temperature = Keyword.get(opts, :temperature, 0.7)
    max_tokens = Keyword.get(opts, :max_tokens, 1000)

    # Get API key from environment
    api_key = System.get_env("GROQ_API_KEY")

    if is_nil(api_key) or api_key == "" do
      {:error, "GROQ_API_KEY environment variable not set"}
    else
      # Build request body
      request_body = %{
        model: model,
        messages: messages,
        temperature: temperature,
        max_tokens: max_tokens
      }

      # Add functions if provided (OpenAI function calling)
      request_body =
        if length(functions) > 0 do
          request_body
          |> Map.put(:functions, functions)
          |> Map.put(:function_call, function_call || "auto")
        else
          request_body
        end

      # Add tools if provided (OpenAI tool calling)
      request_body =
        if length(tools) > 0 do
          request_body
          |> Map.put(:tools, tools)
          |> Map.put(:tool_choice, tool_choice || "auto")
        else
          request_body
        end

      # Make request
      case HTTPoison.post(
             "#{@groq_api_url}/chat/completions",
             Jason.encode!(request_body),
             [
               {"Authorization", "Bearer #{api_key}"},
               {"Content-Type", "application/json"}
             ],
             recv_timeout: 30_000
           ) do
        {:ok, %{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, response} -> {:ok, response}
            {:error, reason} -> {:error, "Failed to parse response: #{reason}"}
          end

        {:ok, %{status_code: code, body: body}} ->
          {:error, "Groq API error: #{code} - #{body}"}

        {:error, reason} ->
          {:error, "Groq request failed: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Generate embeddings using Groq.
  """
  def embeddings(opts) do
    model = Keyword.get(opts, :model, "text-embedding-3-small")
    input = Keyword.get(opts, :input, "")

    # Get API key from environment
    api_key = System.get_env("GROQ_API_KEY")

    if is_nil(api_key) or api_key == "" do
      {:error, "GROQ_API_KEY environment variable not set"}
    else
      # Build request body
      request_body = %{
        model: model,
        input: input
      }

      # Make request
      case HTTPoison.post(
             "#{@groq_api_url}/embeddings",
             Jason.encode!(request_body),
             [
               {"Authorization", "Bearer #{api_key}"},
               {"Content-Type", "application/json"}
             ],
             recv_timeout: 15_000
           ) do
        {:ok, %{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, response} -> {:ok, response}
            {:error, reason} -> {:error, "Failed to parse response: #{reason}"}
          end

        {:ok, %{status_code: code, body: body}} ->
          {:error, "Groq API error: #{code} - #{body}"}

        {:error, reason} ->
          {:error, "Groq request failed: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Check if Groq is available.
  """
  def health_check do
    api_key = System.get_env("GROQ_API_KEY")

    if is_nil(api_key) or api_key == "" do
      {:error, "GROQ_API_KEY not set"}
    else
      case HTTPoison.get(
             "#{@groq_api_url}/models",
             [
               {"Authorization", "Bearer #{api_key}"},
               {"Content-Type", "application/json"}
             ]
           ) do
        {:ok, %{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, %{"data" => models}} ->
              # Filter for embedding models
              embedding_models = Enum.filter(models, fn model ->
                model["object"] == "model" and
                String.contains?(model["id"] || "", "embed")
              end)
              {:ok, "Groq is available with #{length(embedding_models)} embedding models"}

            _ ->
              {:ok, "Groq is available"}
          end

        {:ok, %{status_code: code}} ->
          {:error, "Groq returned status #{code}"}

        {:error, reason} ->
          {:error, "Groq health check failed: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  List available models on Groq.
  """
  def list_models do
    api_key = System.get_env("GROQ_API_KEY")

    if is_nil(api_key) or api_key == "" do
      {:error, "GROQ_API_KEY not set"}
    else
      case HTTPoison.get(
             "#{@groq_api_url}/models",
             [
               {"Authorization", "Bearer #{api_key}"},
               {"Content-Type", "application/json"}
             ]
           ) do
        {:ok, %{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, %{"data" => models}} ->
              {:ok, models}

            {:error, reason} ->
              {:error, "Failed to parse models response: #{reason}"}

            _ ->
              {:error, "Unexpected models response format"}
          end

        {:ok, %{status_code: code, body: body}} ->
          {:error, "Groq models API error: #{code} - #{body}"}

        {:error, reason} ->
          {:error, "Groq models request failed: #{inspect(reason)}"}
      end
    end
  end
end
