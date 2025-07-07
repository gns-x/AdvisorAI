defmodule AdvisorAi.AI.TogetherClient do
  @moduledoc """
  Client for interacting with Together AI API.
  """

  @together_api_url "https://api.together.xyz/v1"

  @doc """
  Generate a chat completion using Together AI.
  """
  def chat_completion(opts) do
    model = Keyword.get(opts, :model, "meta-llama/Llama-3.3-70B-Instruct-Turbo-Free")
    messages = Keyword.get(opts, :messages, [])
    functions = Keyword.get(opts, :functions, [])
    function_call = Keyword.get(opts, :function_call, nil)
    tools = Keyword.get(opts, :tools, [])
    tool_choice = Keyword.get(opts, :tool_choice, nil)
    temperature = Keyword.get(opts, :temperature, 0.7)
    max_tokens = Keyword.get(opts, :max_tokens, 1000)

    # Get API key from environment
    api_key = System.get_env("TOGETHER_API_KEY")

    if is_nil(api_key) or api_key == "" do
      {:error, "TOGETHER_API_KEY environment variable not set"}
    else
      # Build request body
      request_body = %{
        model: model,
        messages: messages,
        temperature: temperature,
        max_tokens: max_tokens,
        stream: false
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

      http_opts = [timeout: 30_000, recv_timeout: 120_000]

      case HTTPoison.post(
             "#{@together_api_url}/chat/completions",
             Jason.encode!(request_body),
             [
               {"Authorization", "Bearer #{api_key}"},
               {"Content-Type", "application/json"}
             ],
             http_opts
           ) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, response} ->
              # Transform to match expected format
              case response do
                %{"choices" => [%{"message" => message} | _]} ->
                  # Check if there are tool calls
                  case message do
                    %{"tool_calls" => tool_calls}
                    when is_list(tool_calls) and length(tool_calls) > 0 ->
                      {:ok,
                       %{
                         "choices" => [
                           %{"message" => %{"content" => "", "tool_calls" => tool_calls}}
                         ]
                       }}

                    _ ->
                      {:ok,
                       %{"choices" => [%{"message" => %{"content" => message["content"] || ""}}]}}
                  end

                _ ->
                  {:error, "Unexpected response format from Together AI"}
              end

            {:error, reason} ->
              {:error, "Failed to parse Together AI response: #{inspect(reason)}"}
          end

        {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
          {:error, "Together AI API error: #{status_code} - #{body}"}

        {:error, %HTTPoison.Error{reason: reason}} ->
          {:error, "HTTP error: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Generate embeddings using Together AI.
  """
  def embeddings(opts) do
    model = Keyword.get(opts, :model, "togethercomputer/m2-bert-80M-8k-base")
    input = Keyword.get(opts, :input, "")

    api_key = System.get_env("TOGETHER_API_KEY")

    if is_nil(api_key) or api_key == "" do
      {:error, "TOGETHER_API_KEY environment variable not set"}
    else
      request_body = %{
        model: model,
        input: input
      }

      http_opts = [timeout: 30_000, recv_timeout: 120_000]

      case HTTPoison.post(
             "#{@together_api_url}/embeddings",
             Jason.encode!(request_body),
             [
               {"Authorization", "Bearer #{api_key}"},
               {"Content-Type", "application/json"}
             ],
             http_opts
           ) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, %{"data" => [%{"embedding" => embedding} | _]}} ->
              {:ok, %{"embedding" => embedding}}

            {:error, reason} ->
              {:error, "Failed to parse Together AI embeddings response: #{inspect(reason)}"}
          end

        {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
          {:error, "Together AI embeddings API error: #{status_code} - #{body}"}

        {:error, %HTTPoison.Error{reason: reason}} ->
          {:error, "HTTP error: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Check if Together AI is accessible.
  """
  def health_check do
    api_key = System.get_env("TOGETHER_API_KEY")

    if is_nil(api_key) or api_key == "" do
      {:error, "TOGETHER_API_KEY environment variable not set"}
    else
      case HTTPoison.get("#{@together_api_url}/models", [
             {"Authorization", "Bearer #{api_key}"}
           ]) do
        {:ok, %HTTPoison.Response{status_code: 200}} ->
          {:ok, "Together AI is accessible"}

        {:ok, %HTTPoison.Response{status_code: status_code}} ->
          {:error, "Together AI health check failed: #{status_code}"}

        {:error, %HTTPoison.Error{reason: reason}} ->
          {:error, "Together AI is not accessible: #{inspect(reason)}"}
      end
    end
  end
end
