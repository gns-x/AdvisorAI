defmodule AdvisorAi.AI.OpenRouterClient do
  @moduledoc """
  Client for interacting with OpenRouter API (OpenAI-compatible).
  """

  @openrouter_api_url "https://openrouter.ai/api/v1"

  @doc """
  Generate a chat completion using OpenRouter.
  """
  def chat_completion(opts) do
    model = Keyword.get(opts, :model, "openai/gpt-4o")
    messages = Keyword.get(opts, :messages, [])
    functions = Keyword.get(opts, :functions, [])
    function_call = Keyword.get(opts, :function_call, nil)
    tools = Keyword.get(opts, :tools, [])
    tool_choice = Keyword.get(opts, :tool_choice, nil)
    temperature = Keyword.get(opts, :temperature, 0.7)
    max_tokens = Keyword.get(opts, :max_tokens, 1000)

    # Get API key from environment
    api_key = System.get_env("OPENROUTER_API_KEY")

    if is_nil(api_key) or api_key == "" do
      {:error, "OPENROUTER_API_KEY environment variable not set"}
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
             "#{@openrouter_api_url}/chat/completions",
             Jason.encode!(request_body),
             [
               {"Authorization", "Bearer #{api_key}"},
               {"Content-Type", "application/json"},
               {"HTTP-Referer", "https://advisor-ai.local"},
               {"X-Title", "AdvisorAI"}
             ],
             recv_timeout: 30_000
           ) do
        {:ok, %{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, response} -> {:ok, response}
            {:error, reason} -> {:error, "Failed to parse response: #{reason}"}
          end

        {:ok, %{status_code: code, body: body}} ->
          {:error, "OpenRouter API error: #{code} - #{body}"}

        {:error, reason} ->
          {:error, "OpenRouter request failed: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Generate embeddings using OpenRouter.
  """
  def embeddings(opts) do
    model = Keyword.get(opts, :model, "openai/text-embedding-ada-002")
    input = Keyword.get(opts, :input, "")

    # Get API key from environment
    api_key = System.get_env("OPENROUTER_API_KEY")

    if is_nil(api_key) or api_key == "" do
      {:error, "OPENROUTER_API_KEY environment variable not set"}
    else
      # Build request body
      request_body = %{
        model: model,
        input: input
      }

      # Make request
      case HTTPoison.post(
             "#{@openrouter_api_url}/embeddings",
             Jason.encode!(request_body),
             [
               {"Authorization", "Bearer #{api_key}"},
               {"Content-Type", "application/json"},
               {"HTTP-Referer", "https://advisor-ai.local"},
               {"X-Title", "AdvisorAI"}
             ],
             recv_timeout: 15_000
           ) do
        {:ok, %{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, response} -> {:ok, response}
            {:error, reason} -> {:error, "Failed to parse response: #{reason}"}
          end

        {:ok, %{status_code: code, body: body}} ->
          {:error, "OpenRouter API error: #{code} - #{body}"}

        {:error, reason} ->
          {:error, "OpenRouter request failed: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Check if OpenRouter is available.
  """
  def health_check do
    api_key = System.get_env("OPENROUTER_API_KEY")

    if is_nil(api_key) or api_key == "" do
      {:error, "OPENROUTER_API_KEY not set"}
    else
      case HTTPoison.get(
             "#{@openrouter_api_url}/models",
             [
               {"Authorization", "Bearer #{api_key}"},
               {"Content-Type", "application/json"}
             ]
           ) do
        {:ok, %{status_code: 200}} ->
          {:ok, "OpenRouter is available"}

        {:ok, %{status_code: code}} ->
          {:error, "OpenRouter returned status #{code}"}

        {:error, reason} ->
          {:error, "OpenRouter health check failed: #{inspect(reason)}"}
      end
    end
  end
end
