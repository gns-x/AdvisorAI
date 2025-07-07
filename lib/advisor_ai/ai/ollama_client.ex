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
    tools = Keyword.get(opts, :tools, [])
    temperature = Keyword.get(opts, :temperature, 0.7)
    max_tokens = Keyword.get(opts, :max_tokens, 1000)

    # Convert messages to Ollama chat format
    ollama_messages = convert_messages_to_ollama_format(messages)

    request_body = %{
      model: model,
      messages: ollama_messages,
      stream: false,
      options: %{
        temperature: temperature,
        num_predict: max_tokens
      }
    }

    http_opts = [timeout: 30_000, recv_timeout: 120_000]

    case HTTPoison.post(
           "#{@ollama_url}/api/chat",
           Jason.encode!(request_body),
           [
             {"Content-Type", "application/json"}
           ],
           http_opts
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"message" => %{"content" => response}}} ->
            # Parse response for tool calls
            case parse_tool_calls(response) do
              {:ok, tool_calls} when tool_calls != [] ->
                {:ok,
                 %{"choices" => [%{"message" => %{"content" => "", "tool_calls" => tool_calls}}]}}

              _ ->
                {:ok, %{"choices" => [%{"message" => %{"content" => response}}]}}
            end

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

    http_opts = [timeout: 30_000, recv_timeout: 120_000]

    case HTTPoison.post(
           "#{@ollama_url}/api/embeddings",
           Jason.encode!(request_body),
           [
             {"Content-Type", "application/json"}
           ],
           http_opts
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"embedding" => embedding}} ->
            {:ok, %{"embedding" => embedding}}

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

  defp convert_messages_to_ollama_format(messages) do
    messages
    |> Enum.map(fn
      # Accept both string and atom keys for role/content
      %{role: role, content: content} when role in ["system", :system] ->
        %{role: "system", content: content}

      %{role: role, content: content} when role in ["user", :user] ->
        %{role: "user", content: content}

      %{role: role, content: content} when role in ["assistant", :assistant] ->
        %{role: "assistant", content: content}

      %{role: role, content: content, tool_call_id: tool_call_id} when role in ["tool", :tool] ->
        %{role: "user", content: "Tool Result (#{tool_call_id}): #{content}"}

      # Fallback for string-keyed maps
      %{"role" => role, "content" => content} when role in ["system", :system] ->
        %{role: "system", content: content}

      %{"role" => role, "content" => content} when role in ["user", :user] ->
        %{role: "user", content: content}

      %{"role" => role, "content" => content} when role in ["assistant", :assistant] ->
        %{role: "assistant", content: content}

      %{"role" => role, "content" => content, "tool_call_id" => tool_call_id}
      when role in ["tool", :tool] ->
        %{role: "user", content: "Tool Result (#{tool_call_id}): #{content}"}

      # Fallback: stringify role/content if present
      msg ->
        %{
          role: to_string(Map.get(msg, :role) || Map.get(msg, "role") || "user"),
          content: Map.get(msg, :content) || Map.get(msg, "content") || ""
        }
    end)
  end

  defp build_prompt(messages, tools) do
    base_prompt =
      messages
      |> Enum.map(fn
        %{role: "system", content: content} ->
          "System: #{content}\n"

        %{role: "user", content: content} ->
          "User: #{content}\n"

        %{role: "assistant", content: content} ->
          "Assistant: #{content}\n"

        %{role: "tool", content: content, tool_call_id: tool_call_id} ->
          "Tool Result (#{tool_call_id}): #{content}\n"
      end)
      |> Enum.join("")

    tools_prompt =
      if length(tools) > 0 do
        tools_json = Jason.encode!(tools)

        "\n\nAvailable tools:\n#{tools_json}\n\nYou can use these tools by calling them in your response. If you need to use a tool, respond with the tool call in JSON format.\n"
      else
        ""
      end

    base_prompt <> tools_prompt <> "Assistant: "
  end

  defp parse_tool_calls(response) do
    # Try to parse JSON tool calls from the response
    case Regex.run(~r/\{.*\}/s, response) do
      [json_str] ->
        case Jason.decode(json_str) do
          {:ok, %{"tool_calls" => tool_calls}} when is_list(tool_calls) ->
            {:ok, tool_calls}

          {:ok, %{"function" => function_call}} ->
            # Single function call
            {:ok,
             [
               %{
                 "id" => "call_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}",
                 "function" => function_call
               }
             ]}

          _ ->
            {:ok, []}
        end

      _ ->
        {:ok, []}
    end
  end
end
