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
  Since Groq doesn't have dedicated embedding models, we use the chat completion model
  to generate embeddings by asking it to return a numerical representation.
  """
  def embeddings(opts) do
    input = Keyword.get(opts, :input, "")

    # Get API key from environment
    api_key = System.get_env("GROQ_API_KEY")

    if is_nil(api_key) or api_key == "" do
      {:error, "GROQ_API_KEY environment variable not set"}
    else
      # Use chat completion to generate embeddings
      # This is a workaround since Groq doesn't have dedicated embedding models
      embedding_prompt = """
      Convert the following text into a numerical embedding representation.
      Return ONLY a JSON array of 1536 floating-point numbers between -1 and 1.
      Do not include any explanation or other text.

      Text: #{input}

      Response format: [0.123, -0.456, 0.789, ...]
      """

      case chat_completion(
             messages: [
               %{role: "system", content: "You are an embedding generator. Return only numerical arrays."},
               %{role: "user", content: embedding_prompt}
             ],
             model: "llama-3.3-70b-versatile",
             temperature: 0.0,
             max_tokens: 2000
           ) do
        {:ok, %{"choices" => [%{"message" => %{"content" => content}}]}} ->
          # Parse the numerical array from the response
          case parse_embedding_response(content) do
            {:ok, embedding} ->
              # Format as OpenAI-compatible response
              {:ok, %{
                "data" => [
                  %{
                    "embedding" => embedding,
                    "index" => 0,
                    "object" => "embedding"
                  }
                ],
                "model" => "llama-3.3-70b-versatile",
                "object" => "list",
                "usage" => %{
                  "prompt_tokens" => 0,
                  "total_tokens" => 0
                }
              }}

            {:error, reason} ->
              {:error, "Failed to parse embedding: #{reason}"}
          end

        {:error, reason} ->
          {:error, "Failed to generate embedding: #{reason}"}
      end
    end
  end

  # Parse embedding response from chat completion
  defp parse_embedding_response(content) do
    # Try to extract JSON array from the response
    case Regex.run(~r/\[([\d\-\.,\s]+)\]/, content) do
      [_, numbers_str] ->
        # Convert string of numbers to list of floats
        numbers = numbers_str
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(fn num_str ->
          case Float.parse(num_str) do
            {num, _} -> num
            :error -> 0.0
          end
        end)

        # Ensure we have exactly 1536 dimensions
        case length(numbers) do
          len when len >= 1536 ->
            {:ok, Enum.take(numbers, 1536)}
          len when len < 1536 ->
            # Pad with zeros if too short
            padding = List.duplicate(0.0, 1536 - len)
            {:ok, numbers ++ padding}
          _ ->
            {:error, "Invalid embedding length: #{length(numbers)}"}
        end

      _ ->
        # Fallback: generate a simple hash-based embedding
        {:ok, generate_hash_embedding(content)}
    end
  end

  # Generate a simple hash-based embedding as fallback
  defp generate_hash_embedding(text) do
    # Use a simple hash function to generate consistent embeddings
    hash = :crypto.hash(:sha256, text)
    |> Base.encode16()
    |> String.slice(0, 1536)
    |> String.graphemes()
    |> Enum.chunk_every(2)
    |> Enum.map(fn [a, b] ->
      # Convert hex pairs to float between -1 and 1
      hex = a <> b
      case Integer.parse(hex, 16) do
        {num, _} -> (num / 255.0) * 2.0 - 1.0
        :error -> 0.0
      end
    end)

    # Ensure we have exactly 1536 dimensions
    case length(hash) do
      len when len >= 1536 ->
        Enum.take(hash, 1536)
      len when len < 1536 ->
        # Pad with zeros if too short
        padding = List.duplicate(0.0, 1536 - len)
        hash ++ padding
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
              # Check for chat completion models (we use these for embeddings too)
              chat_models = Enum.filter(models, fn model ->
                model["object"] == "model" and
                (String.contains?(model["id"] || "", "llama") or
                 String.contains?(model["id"] || "", "mixtral") or
                 String.contains?(model["id"] || "", "gemma"))
              end)
              {:ok, "Groq is available with #{length(chat_models)} chat models (used for embeddings)"}

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
