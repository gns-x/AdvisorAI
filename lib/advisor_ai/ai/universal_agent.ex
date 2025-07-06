defmodule AdvisorAi.AI.UniversalAgent do
  @moduledoc """
  Universal AI Agent that can perform any Gmail/Calendar action based on natural language prompts.
  Uses tool calling to autonomously generate and execute API calls without hard-coded function mappings.
  """

  alias AdvisorAi.{Accounts, Chat, AI}
  alias AdvisorAi.Integrations.{Gmail, Calendar, HubSpot, GoogleContacts}
  alias AI.{OpenRouterClient, TogetherClient, OllamaClient}

  @doc """
  Process any user request and autonomously perform the appropriate Gmail/Calendar actions.
  The AI decides what to do based on the prompt, not predefined function mappings.
  """
  def process_request(user, conversation_id, user_message) do
    conversation = get_conversation_with_context(conversation_id, user.id)
    user_context = get_comprehensive_user_context(user)

    # Build context for AI
    context = build_ai_context(user, conversation, user_context)

    # Get available tools (Gmail/Calendar API capabilities)
    tools = get_available_tools(user)

    # Create AI prompt for universal action understanding
    prompt = build_universal_prompt(user_message, context, tools)

    IO.puts("DEBUG: Universal Agent - Processing: #{user_message}")
    IO.puts("DEBUG: Available tools: #{length(tools)}")

    # Get AI response with tool calls
    case get_ai_response_with_tools(prompt, tools) do
      {:ok, ai_response} ->
        IO.puts("DEBUG: AI Response: #{inspect(ai_response)}")
        execute_ai_tool_calls(user, conversation_id, ai_response, user_message, context)

      {:error, reason} ->
        IO.puts("AI Error: #{reason}")
        create_agent_response(user, conversation_id, "I'm having trouble understanding your request. Please try rephrasing it.", "error")
    end
  end

  # Build comprehensive context for AI
  defp build_ai_context(user, conversation, _user_context) do
    %{
      user: %{
        name: user.name || "User",
        email: user.email,
        google_connected: has_valid_google_tokens?(user),
        gmail_available: has_gmail_access?(user),
        calendar_available: has_calendar_access?(user)
      },
      conversation: get_conversation_summary(conversation),
      recent_messages: get_recent_messages(conversation),
      current_time: DateTime.utc_now()
    }
  end

  # Get all available Gmail/Calendar tools as a schema
  defp get_available_tools(user) do
    [
      # Universal Action Tool - Handles ANY request dynamically
      %{
        name: "universal_action",
        description: "Execute any action related to Gmail, Calendar, Contacts, or OAuth. This is a flexible tool that can handle any request by interpreting the action name and parameters. Examples: search emails, send email, list events, create event, search contacts, check permissions, etc.",
        parameters: %{
          type: "object",
          properties: %{
            action: %{
              type: "string",
              description: "The action to perform (e.g., 'search_emails', 'send_email', 'list_events', 'create_event', 'search_contacts', 'check_permissions', 'delete_email', 'update_event', etc.)"
            },
            query: %{
              type: "string",
              description: "Search query for emails or contacts"
            },
            to: %{
              type: "string",
              description: "Recipient email address"
            },
            subject: %{
              type: "string",
              description: "Email subject line"
            },
            body: %{
              type: "string",
              description: "Email body content"
            },
            max_results: %{
              type: "integer",
              description: "Maximum number of results to return",
              default: 10
            },
            summary: %{
              type: "string",
              description: "Event title/summary"
            },
            start_time: %{
              type: "string",
              description: "Event start time (ISO 8601 format)"
            },
            end_time: %{
              type: "string",
              description: "Event end time (ISO 8601 format)"
            },
            attendees: %{
              type: "array",
              items: %{type: "string"},
              description: "List of attendee email addresses"
            },
            message_id: %{
              type: "string",
              description: "Gmail message ID for operations on specific emails"
            },
            event_id: %{
              type: "string",
              description: "Calendar event ID for operations on specific events"
            }
          },
          required: ["action"]
        }
      }
    ]

    # For universal action, we don't need to filter - it handles all services
    # Just check if user has any Google access
    if has_valid_google_tokens?(user) do
      [
        %{
          name: "universal_action",
          description: "Execute any action related to Gmail, Calendar, Contacts, or OAuth. This is a flexible tool that can handle any request by interpreting the action name and parameters. Examples: search emails, send email, list events, create event, search contacts, check permissions, etc.",
          parameters: %{
            type: "object",
            properties: %{
              action: %{
                type: "string",
                description: "The action to perform (e.g., 'search_emails', 'send_email', 'list_events', 'create_event', 'search_contacts', 'check_permissions', 'delete_email', 'update_event', etc.)"
              },
              query: %{
                type: "string",
                description: "Search query for emails or contacts"
              },
              to: %{
                type: "string",
                description: "Recipient email address"
              },
              subject: %{
                type: "string",
                description: "Email subject line"
              },
              body: %{
                type: "string",
                description: "Email body content"
              },
              max_results: %{
                type: "integer",
                description: "Maximum number of results to return",
                default: 10
              },
              summary: %{
                type: "string",
                description: "Event title/summary"
              },
              start_time: %{
                type: "string",
                description: "Event start time (ISO 8601 format)"
              },
              end_time: %{
                type: "string",
                description: "Event end time (ISO 8601 format)"
              },
              attendees: %{
                type: "array",
                items: %{type: "string"},
                description: "List of attendee email addresses"
              },
              message_id: %{
                type: "string",
                description: "Gmail message ID for operations on specific emails"
              },
              event_id: %{
                type: "string",
                description: "Calendar event ID for operations on specific events"
              }
            },
            required: ["action"]
          }
        }
      ]
    else
      []
    end
  end

  # Build AI prompt for universal action understanding
  defp build_universal_prompt(user_message, context, tools) do
    tools_description = Enum.map_join(tools, "\n", fn tool ->
      {name, description, parameters} = case tool do
        %{function: %{name: n, description: d, parameters: p}} -> {n, d, p}
        %{name: n, description: d, parameters: p} -> {n, d, p}
        _ -> {"unknown", "No description", %{}}
      end

      """
      - #{name}: #{description}
        Parameters: #{Jason.encode!(parameters)}
      """
    end)

    """
    You are an intelligent AI assistant with full access to Gmail and Google Calendar APIs.
    The user said: "#{user_message}"

    User Context:
    - Name: #{context.user.name}
    - Email: #{context.user.email}
    - Google Connected: #{context.user.google_connected}
    - Gmail Available: #{context.user.gmail_available}
    - Calendar Available: #{context.user.calendar_available}
    - Current Time: #{context.current_time}

    Available Tools:
    #{tools_description}

    CRITICAL INSTRUCTIONS:
    1. You MUST use function calling to execute actions
    2. DO NOT provide any explanations, plans, or JSON in your text response
    3. DO NOT describe what you will do - just execute the function calls
    4. The user wants ONLY the final result, not your reasoning
    5. If you cannot execute a function call, respond with a brief error message
    6. NEVER show JSON examples in your response - use actual function calls
    7. NEVER say "Let me execute..." or "I'll use..." - just execute

    Examples of what NOT to do:
    - "I'll search for your last sent email using gmail_list_messages..."
    - "Let me execute the gmail_list_messages function..."
    - "Here's what I'm doing: * Using gmail_list_messages..."
    - "Here's the tool call: ```json {...}```"
    - "Let me execute these tool calls and retrieve your email..."

    Examples of what TO do:
    - Just call the appropriate function with the right parameters
    - Let the function execution provide the result
    - Use actual function calling, not text descriptions

    For "give me my last sent email": Call gmail_list_messages with query="in:sent" and max_results=1
    For "send email to john@example.com": Call gmail_send_message with to="john@example.com", subject="Email", body="Hello"
    """
  end

  # Get AI response with tool calls using OpenRouter (supports function calling)
  defp get_ai_response_with_tools(prompt, tools) do
    # Convert tools to OpenRouter tool calling format (newer format)
    tools_format = Enum.map(tools, fn tool ->
      {name, description, parameters} = case tool do
        %{function: %{name: n, description: d, parameters: p}} -> {n, d, p}
        %{name: n, description: d, parameters: p} -> {n, d, p}
        _ -> {"unknown", "No description", %{}}
      end

      %{
        type: "function",
        function: %{
          name: name,
          description: description,
          parameters: parameters
        }
      }
    end)

    messages = [
      %{"role" => "system", "content" => "You are a helpful AI assistant with access to Gmail and Calendar APIs. Use the available tools to help users. DO NOT provide explanations - just execute tools."},
      %{"role" => "user", "content" => prompt}
    ]

    case OpenRouterClient.chat_completion(
      messages: messages,
      tools: tools_format,
      tool_choice: "auto",
      temperature: 0.1
    ) do
      {:ok, response} -> {:ok, response}
      {:error, _} ->
        # Fallback to Together AI
        case TogetherClient.chat_completion(
          messages: messages,
          tools: tools_format,
          tool_choice: "auto",
          temperature: 0.1
        ) do
          {:ok, response} -> {:ok, response}
          {:error, _} ->
            # Final fallback to Ollama (basic response without function calling)
            case OllamaClient.chat_completion(messages: messages, temperature: 0.1) do
              {:ok, response} -> {:ok, response}
              {:error, reason} -> {:error, reason}
            end
        end
    end
  end

  # Execute AI tool calls
  defp execute_ai_tool_calls(user, conversation_id, ai_response, user_message, context) do
    case parse_tool_calls(ai_response) do
      {:ok, tool_calls} when tool_calls != [] ->
        # Execute each tool call
        results = Enum.map(tool_calls, fn tool_call ->
          execute_tool_call(user, tool_call)
        end)

        # Only show the actual result(s), not the plan or tool call JSON
        response_text =
          results
          |> Enum.map(fn
            {:ok, result} -> result
            {:error, error} -> "Error: #{error}"
          end)
          |> Enum.join("\n\n")

        create_agent_response(user, conversation_id, response_text, "action")

      {:ok, []} ->
        # No tool calls found, try to extract JSON from the AI's text response
        response_text = extract_text_response(ai_response)

        case extract_and_execute_json_from_text(user, response_text, context) do
          {:ok, result} ->
            create_agent_response(user, conversation_id, result, "action")

          {:error, _} ->
            # If no JSON found, try to force execution based on user message
            case force_execute_based_on_message(user, user_message, context) do
              {:ok, result} ->
                create_agent_response(user, conversation_id, result, "action")
              {:error, _} ->
                create_agent_response(user, conversation_id, "I understand your request but need to use the available tools to help you. Let me try a different approach.", "conversation")
            end
        end

      {:error, reason} ->
        IO.puts("Failed to parse tool calls: #{reason}")
        response_text = extract_text_response(ai_response)

        case extract_and_execute_json_from_text(user, response_text, context) do
          {:ok, result} ->
            create_agent_response(user, conversation_id, result, "action")

          {:error, _} ->
            # Try to force execution based on user message
            case force_execute_based_on_message(user, user_message, context) do
              {:ok, result} ->
                create_agent_response(user, conversation_id, result, "action")
              {:error, _} ->
                create_agent_response(user, conversation_id, "I understand your request but couldn't execute the necessary actions. Please try rephrasing.", "error")
            end
        end
    end
  end

  # Parse tool calls from AI response
  defp parse_tool_calls(response) do
    case response do
      %{"choices" => [%{"message" => %{"tool_calls" => tool_calls}} | _]} ->
        # Convert tool calls to function call format for compatibility
        function_calls = Enum.map(tool_calls, fn tool_call ->
          %{
            "name" => tool_call["function"]["name"],
            "arguments" => tool_call["function"]["arguments"]
          }
        end)
        {:ok, function_calls}

      %{"choices" => [%{"message" => %{"function_call" => function_call}} | _]} ->
        {:ok, [function_call]}

      %{"choices" => [%{"message" => %{"content" => content}} | _]} ->
        # Try to extract function calls from content (fallback)
        case extract_function_calls_from_content(content) do
          {:ok, calls} -> {:ok, calls}
          {:error, _} -> {:ok, []}
        end

      _ ->
        {:error, "Unexpected response format"}
    end
  end

  # Extract function calls from content (fallback method)
  defp extract_function_calls_from_content(content) do
    # Look for JSON function calls in the content
    case Regex.run(~r/\{\s*"name":\s*"([^"]+)",\s*"arguments":\s*(\{[^}]+\})/, content) do
      [_, name, args_json] ->
        case Jason.decode(args_json) do
          {:ok, args} -> {:ok, [%{"name" => name, "arguments" => args}]}
          {:error, _} -> {:error, "Invalid arguments JSON"}
        end
      _ ->
        {:error, "No function calls found"}
    end
  end

  # Extract text response from AI response
  defp extract_text_response(response) do
    case response do
      %{"choices" => [%{"message" => %{"content" => content}} | _]} ->
        content
      _ ->
        nil
    end
  end

  # Execute a single tool call
  defp execute_tool_call(user, tool_call) do
    function_name = tool_call["name"]
    raw_arguments = tool_call["arguments"] || %{}

    # Parse arguments if they're a JSON string
    arguments = case raw_arguments do
      args when is_binary(args) ->
        case Jason.decode(args) do
          {:ok, parsed_args} -> parsed_args
          {:error, _} -> %{}
        end
      args when is_map(args) ->
        args
      _ ->
        %{}
    end

    IO.puts("DEBUG: Executing tool: #{function_name} with args: #{inspect(arguments)}")

    # Universal dynamic execution - no hardcoded cases needed
    case function_name do
      "universal_action" -> execute_universal_action(user, arguments)
      _ -> execute_universal_action(user, function_name, arguments)
    end
  end

    # Universal Action Execution - Handles ANY request dynamically
  defp execute_universal_action(user, args) do
    # Extract action from args
    action = Map.get(args, "action", "")
    action_lower = String.downcase(action)

    cond do
      # Gmail actions
      String.contains?(action_lower, "search") and (String.contains?(action_lower, "email") or String.contains?(action_lower, "mail")) ->
        query = Map.get(args, "query", "")
        max_results = Map.get(args, "max_results", 10)
        execute_gmail_action(user, "search", %{query: query, max_results: max_results})

      String.contains?(action_lower, "send") and (String.contains?(action_lower, "email") or String.contains?(action_lower, "mail")) ->
        execute_gmail_action(user, "send", args)

      String.contains?(action_lower, "list") and (String.contains?(action_lower, "email") or String.contains?(action_lower, "mail")) ->
        execute_gmail_action(user, "list", args)

      String.contains?(action_lower, "delete") and (String.contains?(action_lower, "email") or String.contains?(action_lower, "mail")) ->
        execute_gmail_action(user, "delete", args)

      # Calendar actions
      String.contains?(action_lower, "list") and (String.contains?(action_lower, "event") or String.contains?(action_lower, "calendar")) ->
        execute_calendar_action(user, "list", args)

      String.contains?(action_lower, "create") and (String.contains?(action_lower, "event") or String.contains?(action_lower, "calendar")) ->
        execute_calendar_action(user, "create", args)

      String.contains?(action_lower, "update") and (String.contains?(action_lower, "event") or String.contains?(action_lower, "calendar")) ->
        execute_calendar_action(user, "update", args)

      String.contains?(action_lower, "delete") and (String.contains?(action_lower, "event") or String.contains?(action_lower, "calendar")) ->
        execute_calendar_action(user, "delete", args)

      # Contact actions
      String.contains?(action_lower, "search") and String.contains?(action_lower, "contact") ->
        execute_contact_action(user, "search", args)

      String.contains?(action_lower, "create") and String.contains?(action_lower, "contact") ->
        execute_contact_action(user, "create", args)

      # OAuth actions
      String.contains?(action_lower, "check") and (String.contains?(action_lower, "permission") or String.contains?(action_lower, "scope") or String.contains?(action_lower, "oauth")) ->
        execute_oauth_action(user, args)

      # Default - try to infer from action name
      true ->
        execute_inferred_action(user, action, args)
    end
  end

  # Legacy support for old function names
  defp execute_universal_action(user, action, args) do
    # Parse the action to determine what to do
    action_lower = String.downcase(action)

    cond do
      # Gmail actions
      String.contains?(action_lower, "gmail") and String.contains?(action_lower, "search") ->
        query = Map.get(args, "query", "")
        max_results = Map.get(args, "max_results", 10)
        execute_gmail_action(user, "search", %{query: query, max_results: max_results})

      String.contains?(action_lower, "gmail") and String.contains?(action_lower, "send") ->
        execute_gmail_action(user, "send", args)

      String.contains?(action_lower, "gmail") and String.contains?(action_lower, "list") ->
        execute_gmail_action(user, "list", args)

      # Calendar actions
      String.contains?(action_lower, "calendar") and String.contains?(action_lower, "list") ->
        execute_calendar_action(user, "list", args)

      String.contains?(action_lower, "calendar") and String.contains?(action_lower, "create") ->
        execute_calendar_action(user, "create", args)

      # Contact actions
      String.contains?(action_lower, "contact") and String.contains?(action_lower, "search") ->
        execute_contact_action(user, "search", args)

      String.contains?(action_lower, "contact") and String.contains?(action_lower, "create") ->
        execute_contact_action(user, "create", args)

      # OAuth actions
      String.contains?(action_lower, "oauth") or String.contains?(action_lower, "scope") ->
        execute_oauth_action(user, args)

      # Default - try to infer from action name
      true ->
        execute_inferred_action(user, action, args)
    end
  end

  # Generic action executors
  defp execute_gmail_action(user, operation, args) do
    case operation do
      "search" ->
        # Handle both string and atom keys
        query = Map.get(args, "query") || Map.get(args, :query) || ""
        max_results = Map.get(args, "max_results") || Map.get(args, :max_results) || 10

        case Gmail.search_emails(user, query) do
          {:ok, emails} ->
            emails_to_show = Enum.take(emails, max_results)
            email_list = Enum.map(emails_to_show, fn email ->
              "• #{email.subject} (from: #{email.from})"
            end) |> Enum.join("\n")

            {:ok, "Found #{length(emails)} emails:\n\n#{email_list}"}
          {:error, reason} ->
            {:error, "Failed to search emails: #{reason}"}
        end

      "send" ->
        to = Map.get(args, "to") || Map.get(args, :to)
        subject = Map.get(args, "subject") || Map.get(args, :subject)
        body = Map.get(args, "body") || Map.get(args, :body)

        case Gmail.send_email(user, to, subject, body) do
          {:ok, _} -> {:ok, "Email sent successfully to #{to}"}
          {:error, reason} -> {:error, "Failed to send email: #{reason}"}
        end

      "list" ->
        query = Map.get(args, "query") || Map.get(args, :query) || ""
        max_results = Map.get(args, "max_results") || Map.get(args, :max_results) || 10

        case Gmail.search_emails(user, query) do
          {:ok, emails} ->
            emails_to_show = Enum.take(emails, max_results)
            email_list = Enum.map(emails_to_show, fn email ->
              "• #{email.subject} (from: #{email.from})"
            end) |> Enum.join("\n")

            {:ok, "Found #{length(emails)} emails:\n\n#{email_list}"}
          {:error, reason} ->
            {:error, "Failed to list emails: #{reason}"}
        end

      "delete" ->
        message_id = Map.get(args, "message_id") || Map.get(args, :message_id)

        case Gmail.delete_message(user, message_id) do
          {:ok, _} -> {:ok, "Email deleted successfully"}
          {:error, reason} -> {:error, "Failed to delete email: #{reason}"}
        end
    end
  end

  defp execute_calendar_action(user, operation, args) do
    case operation do
      "list" ->
        max_results = Map.get(args, "max_results") || Map.get(args, :max_results) || 10
        time_min = Map.get(args, "time_min") || Map.get(args, :time_min)
        time_max = Map.get(args, "time_max") || Map.get(args, :time_max)

        opts = [max_results: max_results]
        opts = if time_min, do: Keyword.put(opts, :time_min, time_min), else: opts
        opts = if time_max, do: Keyword.put(opts, :time_max, time_max), else: opts

        case Calendar.list_events(user, opts) do
          {:ok, events} ->
            if length(events) > 0 do
              event_list = Enum.map(events, fn event ->
                start_time = get_in(event, ["start", "dateTime"]) || get_in(event, ["start", "date"])
                "• #{event["summary"]} (#{start_time})"
              end) |> Enum.join("\n")

              {:ok, "Found #{length(events)} events:\n\n#{event_list}"}
            else
              {:ok, "No events found"}
            end
          {:error, reason} ->
            {:error, "Failed to list events: #{reason}"}
        end

      "create" ->
        event_data = %{
          "title" => Map.get(args, "summary") || Map.get(args, :summary),
          "description" => Map.get(args, "description") || Map.get(args, :description) || "",
          "start_time" => Map.get(args, "start_time") || Map.get(args, :start_time),
          "end_time" => Map.get(args, "end_time") || Map.get(args, :end_time),
          "attendees" => Map.get(args, "attendees") || Map.get(args, :attendees) || []
        }

        case Calendar.create_event(user, event_data) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, "Failed to create event: #{reason}"}
        end

      "update" ->
        event_id = Map.get(args, "event_id") || Map.get(args, :event_id)
        event_data = %{
          "summary" => Map.get(args, "summary") || Map.get(args, :summary),
          "description" => Map.get(args, "description") || Map.get(args, :description) || "",
          "start_time" => Map.get(args, "start_time") || Map.get(args, :start_time),
          "end_time" => Map.get(args, "end_time") || Map.get(args, :end_time),
          "attendees" => Map.get(args, "attendees") || Map.get(args, :attendees) || []
        }

        case Calendar.update_event(user, event_id, event_data) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, "Failed to update event: #{reason}"}
        end

      "delete" ->
        event_id = Map.get(args, "event_id") || Map.get(args, :event_id)

        case Calendar.delete_event(user, event_id) do
          {:ok, _} -> {:ok, "Event deleted successfully"}
          {:error, reason} -> {:error, "Failed to delete event: #{reason}"}
        end
    end
  end

  defp execute_contact_action(user, operation, args) do
    case operation do
      "search" ->
        query = Map.get(args, "query") || Map.get(args, :query) || ""

        case GoogleContacts.search_contacts(user, query) do
          {:ok, contacts} ->
            contact_list = Enum.map(contacts, fn contact ->
              name = get_contact_display_name(contact)
              email = get_contact_primary_email(contact)
              phone = get_contact_primary_phone(contact)

              contact_info = "• #{name}"
              contact_info = if email, do: contact_info <> " (#{email})", else: contact_info
              contact_info = if phone, do: contact_info <> " - #{phone}", else: contact_info

              contact_info
            end) |> Enum.join("\n")

            {:ok, "Found #{length(contacts)} contacts:\n\n#{contact_list}"}
          {:error, reason} ->
            {:error, "Failed to search contacts: #{reason}"}
        end

      "create" ->
        {:ok, "Contact creation not yet implemented"}
    end
  end

  defp execute_oauth_action(user, _args) do
    case Accounts.get_user_google_account(user.id) do
      nil ->
        {:ok, "No Google account connected. Please connect your Google account first."}
      account ->
        scopes = account.scopes || []
        if Enum.empty?(scopes) do
          {:ok, "No OAuth scopes found. You need to reconnect your Google account to grant permissions."}
        else
          scope_descriptions = scopes
          |> Enum.map(fn scope ->
            case scope do
              "https://www.googleapis.com/auth/gmail.modify" -> "Gmail (read & send emails)"
              "https://www.googleapis.com/auth/calendar" -> "Calendar (full access)"
              "https://www.googleapis.com/auth/contacts" -> "Contacts (full access)"
              _ -> scope
            end
          end)

          {:ok, "Current OAuth scopes:\n" <> Enum.join(scope_descriptions, "\n")}
        end
    end
  end

  defp execute_inferred_action(user, action, args) do
    # Try to infer what the user wants based on the action name
    action_lower = String.downcase(action)

    cond do
      String.contains?(action_lower, "email") or String.contains?(action_lower, "mail") ->
        execute_gmail_action(user, "search", args)

      String.contains?(action_lower, "event") or String.contains?(action_lower, "meeting") ->
        execute_calendar_action(user, "list", args)

      String.contains?(action_lower, "contact") or String.contains?(action_lower, "person") ->
        execute_contact_action(user, "search", args)

      true ->
        {:error, "Could not determine how to execute action: #{action}"}
    end
  end

  # Gmail Tool Executions
  defp execute_gmail_search(user, args) do
    query = Map.get(args, "query", "")
    max_results = Map.get(args, "max_results", 10)

    case Gmail.search_emails(user, query) do
      {:ok, emails} ->
        emails_to_show = Enum.take(emails, max_results)
        email_list = Enum.map(emails_to_show, fn email ->
          "• #{email.subject} (from: #{email.from})"
        end) |> Enum.join("\n")

        {:ok, "Found #{length(emails)} emails:\n\n#{email_list}"}

      {:error, reason} ->
        {:error, "Failed to search emails: #{reason}"}
    end
  end

  defp execute_gmail_list_messages(user, args) do
    query = Map.get(args, "query", "")
    max_results = Map.get(args, "max_results", 10)

    case Gmail.search_emails(user, query) do
      {:ok, emails} ->
        emails_to_show = Enum.take(emails, max_results)
        email_list = Enum.map(emails_to_show, fn email ->
          "• #{email.subject} (from: #{email.from})"
        end) |> Enum.join("\n")

        {:ok, "Found #{length(emails)} emails:\n\n#{email_list}"}

      {:error, reason} ->
        {:error, "Failed to list emails: #{reason}"}
    end
  end

  defp execute_gmail_get_message(user, args) do
    message_id = args["message_id"]

    case Gmail.get_email_details(user, message_id) do
      {:ok, email} ->
        {:ok, "Email: #{email.subject}\nFrom: #{email.from}\nDate: #{email.date}\n\n#{email.body}"}

      {:error, reason} ->
        {:error, "Failed to get email: #{reason}"}
    end
  end

  defp execute_gmail_send_message(user, args) do
    to = args["to"]
    subject = args["subject"]
    body = args["body"]

    case Gmail.send_email(user, to, subject, body) do
      {:ok, _} ->
        {:ok, "Email sent successfully to #{to}"}

      {:error, reason} ->
        {:error, "Failed to send email: #{reason}"}
    end
  end

    defp execute_gmail_delete_message(user, args) do
    message_id = args["message_id"]

    case Gmail.delete_message(user, message_id) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, "Failed to delete message: #{reason}"}
    end
  end

  defp execute_gmail_modify_message(user, args) do
    message_id = args["message_id"]
    add_label_ids = Map.get(args, "add_label_ids", [])
    remove_label_ids = Map.get(args, "remove_label_ids", [])

    case Gmail.modify_message(user, message_id, add_label_ids, remove_label_ids) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, "Failed to modify message: #{reason}"}
    end
  end

  defp execute_gmail_create_draft(user, args) do
    to = args["to"]
    subject = args["subject"]
    body = args["body"]

    case Gmail.create_draft(user, to, subject, body) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, "Failed to create draft: #{reason}"}
    end
  end

  defp execute_gmail_get_profile(user, _args) do
    case Gmail.get_profile(user) do
      {:ok, profile} -> {:ok, "Gmail profile: #{profile["emailAddress"]}"}
      {:error, reason} -> {:error, "Failed to get profile: #{reason}"}
    end
  end

  defp execute_gmail_send(user, args) do
    to = args["to"]
    subject = args["subject"]
    body = args["body"]

    case Gmail.send_email(user, to, subject, body) do
      {:ok, _} ->
        {:ok, "Email sent successfully to #{to}"}

      {:error, reason} ->
        {:error, "Failed to send email: #{reason}"}
    end
  end

  # Calendar Tool Executions
  defp execute_calendar_list(user, args) do
    max_results = Map.get(args, "max_results", 10)
    time_min = Map.get(args, "time_min")
    time_max = Map.get(args, "time_max")

    opts = [max_results: max_results]
    opts = if time_min, do: Keyword.put(opts, :time_min, time_min), else: opts
    opts = if time_max, do: Keyword.put(opts, :time_max, time_max), else: opts

    case Calendar.list_events(user, opts) do
      {:ok, events} ->
        if length(events) > 0 do
          event_list = Enum.map(events, fn event ->
            start_time = get_in(event, ["start", "dateTime"]) || get_in(event, ["start", "date"])
            "• #{event["summary"]} (#{start_time})"
          end) |> Enum.join("\n")

          {:ok, "Found #{length(events)} events:\n\n#{event_list}"}
        else
          {:ok, "No events found"}
        end

      {:error, reason} ->
        {:error, "Failed to list events: #{reason}"}
    end
  end

  defp execute_calendar_create(user, args) do
    event_data = %{
      "title" => args["summary"],
      "description" => Map.get(args, "description", ""),
      "start_time" => args["start_time"],
      "end_time" => args["end_time"],
      "attendees" => Map.get(args, "attendees", [])
    }

    case Calendar.create_event(user, event_data) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, "Failed to create event: #{reason}"}
    end
  end

  defp execute_calendar_list_events(user, args) do
    calendar_id = Map.get(args, "calendar_id", "primary")
    time_min = Map.get(args, "time_min")
    time_max = Map.get(args, "time_max")
    max_results = Map.get(args, "max_results", 10)
    q = Map.get(args, "q")

    opts = [
      calendar_id: calendar_id,
      max_results: max_results
    ]
    opts = if time_min, do: Keyword.put(opts, :time_min, time_min), else: opts
    opts = if time_max, do: Keyword.put(opts, :time_max, time_max), else: opts
    opts = if q, do: Keyword.put(opts, :q, q), else: opts

    case Calendar.list_events(user, opts) do
      {:ok, events} ->
        if length(events) > 0 do
          event_list = Enum.map(events, fn event ->
            start_time = get_in(event, ["start", "dateTime"]) || get_in(event, ["start", "date"])
            "• #{event["summary"]} (#{start_time})"
          end) |> Enum.join("\n")

          {:ok, "Found #{length(events)} events:\n\n#{event_list}"}
        else
          {:ok, "No events found"}
        end

      {:error, reason} ->
        {:error, "Failed to list events: #{reason}"}
    end
  end

  defp execute_calendar_get_event(user, args) do
    event_id = args["event_id"]
    _calendar_id = Map.get(args, "calendar_id", "primary")

    case Calendar.get_event(user, event_id) do
      {:ok, event} ->
        start_time = get_in(event, ["start", "dateTime"]) || get_in(event, ["start", "date"])
        end_time = get_in(event, ["end", "dateTime"]) || get_in(event, ["end", "date"])

        {:ok, "Event: #{event["summary"]}\nStart: #{start_time}\nEnd: #{end_time}\nDescription: #{event["description"] || "No description"}"}

      {:error, reason} ->
        {:error, "Failed to get event: #{reason}"}
    end
  end

  defp execute_calendar_create_event(user, args) do
    event_data = %{
      "title" => args["summary"],
      "description" => Map.get(args, "description", ""),
      "start_time" => args["start_time"],
      "end_time" => args["end_time"],
      "attendees" => Map.get(args, "attendees", [])
    }

    case Calendar.create_event(user, event_data) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, "Failed to create event: #{reason}"}
    end
  end

  defp execute_calendar_update_event(user, args) do
    event_id = args["event_id"]
    calendar_id = Map.get(args, "calendar_id", "primary")

    event_data = %{
      "summary" => Map.get(args, "summary"),
      "description" => Map.get(args, "description"),
      "start_time" => Map.get(args, "start_time"),
      "end_time" => Map.get(args, "end_time"),
      "attendees" => Map.get(args, "attendees", [])
    }

    case Calendar.update_event(user, event_id, event_data, calendar_id) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, "Failed to update event: #{reason}"}
    end
  end

  defp execute_calendar_delete_event(user, args) do
    event_id = args["event_id"]
    calendar_id = Map.get(args, "calendar_id", "primary")

    case Calendar.delete_event(user, event_id, calendar_id) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, "Failed to delete event: #{reason}"}
    end
  end

  defp execute_calendar_get_calendars(user, _args) do
    case Calendar.list_calendars(user) do
      {:ok, calendars} ->
        if length(calendars) > 0 do
          calendar_list = Enum.map(calendars, fn calendar ->
            "• #{calendar["summary"]} (#{calendar["id"]})"
          end) |> Enum.join("\n")

          {:ok, "Available calendars:\n\n#{calendar_list}"}
        else
          {:ok, "No calendars found"}
        end

      {:error, reason} ->
        {:error, "Failed to list calendars: #{reason}"}
    end
  end

  # Contact Tool Executions
  defp execute_contacts_search(user, args) do
    query = args["query"]

    case GoogleContacts.search_contacts(user, query) do
      {:ok, contacts} ->
        contact_list = Enum.map(contacts, fn contact ->
          name = get_contact_display_name(contact)
          email = get_contact_primary_email(contact)
          phone = get_contact_primary_phone(contact)

          contact_info = "• #{name}"
          contact_info = if email, do: contact_info <> " (#{email})", else: contact_info
          contact_info = if phone, do: contact_info <> " - #{phone}", else: contact_info

          contact_info
        end) |> Enum.join("\n")

        {:ok, "Found #{length(contacts)} contacts:\n\n#{contact_list}"}

      {:error, reason} ->
        {:error, "Failed to search contacts: #{reason}"}
    end
  end

  defp execute_contacts_create(_user, _args) do
    # Note: This would need to be implemented in the GoogleContacts module
    {:ok, "Contact created"}
  end

  defp execute_check_oauth_scopes(user, _args) do
    case Accounts.get_user_google_account(user.id) do
      nil ->
        {:ok, "No Google account connected. Please connect your Google account first."}

      account ->
        scopes = account.scopes || []

        if Enum.empty?(scopes) do
          {:ok, "No OAuth scopes found. You need to reconnect your Google account to grant permissions."}
        else
          scope_descriptions = scopes
          |> Enum.map(fn scope ->
            case scope do
              "https://www.googleapis.com/auth/gmail.modify" -> "Gmail (read & send emails)"
              "https://www.googleapis.com/auth/calendar" -> "Calendar (full access)"
              "https://www.googleapis.com/auth/calendar.events" -> "Calendar events"
              "https://www.googleapis.com/auth/contacts" -> "Contacts (full access)"
              "https://www.googleapis.com/auth/contacts.readonly" -> "Contacts (read only)"
              "https://www.googleapis.com/auth/drive" -> "Google Drive"
              "https://www.googleapis.com/auth/drive.file" -> "Google Drive files"
              "https://www.googleapis.com/auth/user.emails.read" -> "User emails"
              "https://www.googleapis.com/auth/user.addresses.read" -> "User addresses"
              "https://www.googleapis.com/auth/user.birthday.read" -> "User birthday"
              "https://www.googleapis.com/auth/user.phonenumbers.read" -> "User phone numbers"
              "https://www.googleapis.com/auth/user.organization.read" -> "User organization"
              "https://www.googleapis.com/auth/user.gender.read" -> "User gender"
              "https://www.googleapis.com/auth/userinfo.profile" -> "User profile"
              "https://www.googleapis.com/auth/userinfo.email" -> "User email"
              _ -> scope
            end
          end)

          {:ok, "Current OAuth scopes:\n" <> Enum.join(scope_descriptions, "\n")}
        end
    end
  end

  # Generate response from tool execution results
  defp generate_response_from_results(_user_message, results) do
    successful_results = Enum.filter(results, fn
      {:ok, _} -> true
      {:error, _} -> false
    end)

    error_results = Enum.filter(results, fn
      {:error, _} -> true
      {:ok, _} -> false
    end)

    cond do
      length(successful_results) > 0 and length(error_results) == 0 ->
        # All successful
        responses = Enum.map(successful_results, fn {:ok, response} -> response end)
        Enum.join(responses, "\n\n")

      length(successful_results) > 0 and length(error_results) > 0 ->
        # Mixed results
        success_responses = Enum.map(successful_results, fn {:ok, response} -> response end)
        error_responses = Enum.map(error_results, fn {:error, error} -> "Error: #{error}" end)

        "Some actions completed successfully:\n\n#{Enum.join(success_responses, "\n\n")}\n\nSome actions failed:\n#{Enum.join(error_responses, "\n")}"

      length(error_results) > 0 ->
        # All failed
        error_responses = Enum.map(error_results, fn {:error, error} -> "Error: #{error}" end)
        "I encountered some issues:\n\n#{Enum.join(error_responses, "\n")}"

      true ->
        "I've processed your request."
    end
  end

  # Helper functions (reuse from existing modules)
  defp get_conversation_with_context(conversation_id, user_id) do
    Chat.get_conversation_with_messages!(conversation_id, user_id)
  end

  defp get_comprehensive_user_context(user) do
    # Get user's Google account info
    google_account = Accounts.get_user_google_account(user.id)

    %{
      google_connected: not is_nil(google_account),
      scopes: if(google_account, do: google_account.scopes, else: [])
    }
  end

  defp get_conversation_summary(conversation) do
    case conversation do
      %{messages: messages} when is_list(messages) and length(messages) > 0 ->
        recent_messages = Enum.take(messages, 5)
        Enum.map_join(recent_messages, "\n", fn msg ->
          "#{msg.role}: #{msg.content}"
        end)
      _ ->
        "No recent conversation"
    end
  end

  defp get_recent_messages(conversation) do
    case conversation do
      %{messages: messages} when is_list(messages) -> messages
      _ -> []
    end
  end

  defp has_valid_google_tokens?(user) do
    case Accounts.get_user_google_account(user.id) do
      nil -> false
      account ->
        case account.token_expires_at do
          nil -> true
          expires_at -> DateTime.compare(DateTime.utc_now(), expires_at) == :lt
        end
    end
  end

  defp has_gmail_access?(user) do
    case Accounts.get_user_google_account(user.id) do
      nil -> false
      account ->
        scopes = account.scopes || []
        Enum.any?(scopes, fn scope ->
          String.contains?(scope, "gmail") or String.contains?(scope, "mail")
        end)
    end
  end

  defp has_calendar_access?(user) do
    case Accounts.get_user_google_account(user.id) do
      nil -> false
      account ->
        scopes = account.scopes || []
        Enum.any?(scopes, fn scope ->
          String.contains?(scope, "calendar")
        end)
    end
  end

  defp create_agent_response(_user, conversation_id, content, response_type) do
    Chat.create_message(conversation_id, %{
      role: "assistant",
      content: content,
      metadata: %{response_type: response_type}
    })
  end

  # Helper functions to extract contact information
  defp get_contact_display_name(contact) do
    case contact.names do
      [name | _] -> name.display_name
      _ -> "Unknown"
    end
  end

  defp get_contact_primary_email(contact) do
    case contact.email_addresses do
      [email | _] -> email.value
      _ -> nil
    end
  end

  defp get_contact_primary_phone(contact) do
    case contact.phone_numbers do
      [phone | _] -> phone.value
      _ -> nil
    end
  end

  # Extract JSON from text and execute it as a tool call
  defp extract_and_execute_json_from_text(user, text, context) do
    # Look for JSON blocks in the text
    case Regex.run(~r/```json\s*(\{.*?\})\s*```/s, text) do
      [_, json_str] ->
        case Jason.decode(json_str) do
          {:ok, params} ->
            # Try to determine which tool to use based on the parameters
            tool_name = determine_tool_from_params(params, context)

            if tool_name do
              case execute_tool_call(user, %{"name" => tool_name, "arguments" => params}) do
                {:ok, result} -> {:ok, result}
                {:error, reason} -> {:error, reason}
              end
            else
              {:error, "Could not determine tool from parameters"}
            end

          {:error, _} ->
            {:error, "Invalid JSON"}
        end

      _ ->
        {:error, "No JSON found in text"}
    end
  end

    # Force execution based on user message when AI fails to generate tool calls
  defp force_execute_based_on_message(user, user_message, _context) do
    message_lower = String.downcase(user_message)

    cond do
      # Last sent email
      String.contains?(message_lower, "last sent email") or String.contains?(message_lower, "last email") ->
        execute_tool_call(user, %{"name" => "gmail_list_messages", "arguments" => %{"query" => "in:sent", "max_results" => 1}})

      # Send email
      String.contains?(message_lower, "send email") or String.contains?(message_lower, "email to") ->
        # Extract email and subject from message
        case extract_email_info_from_message(user_message) do
          {:ok, email_info} ->
            execute_tool_call(user, %{"name" => "gmail_send_message", "arguments" => email_info})
          {:error, _} ->
            {:error, "Could not extract email information from message"}
        end

      # Search emails
      String.contains?(message_lower, "find email") or String.contains?(message_lower, "search email") ->
        query = extract_search_query_from_message(user_message)
        execute_tool_call(user, %{"name" => "gmail_list_messages", "arguments" => %{"query" => query, "max_results" => 10}})

      # Calendar events
      String.contains?(message_lower, "schedule") or String.contains?(message_lower, "meeting") ->
        case extract_calendar_info_from_message(user_message) do
          {:ok, calendar_info} ->
            execute_tool_call(user, %{"name" => "calendar_create_event", "arguments" => calendar_info})
          {:error, _} ->
            {:error, "Could not extract calendar information from message"}
        end

      # Check scopes
      String.contains?(message_lower, "check scopes") or String.contains?(message_lower, "what scopes") ->
        case check_user_scopes(user) do
          {:ok, scopes} ->
            {:ok, "Your current Google scopes:\n\n#{Enum.join(scopes, "\n")}"}
          {:error, reason} ->
            {:error, "Could not check scopes: #{reason}"}
        end

      # Default to recent emails
      true ->
        execute_tool_call(user, %{"name" => "gmail_list_messages", "arguments" => %{"query" => "", "max_results" => 5}})
    end
  end

  # Check user's current Google scopes
  defp check_user_scopes(user) do
    case Accounts.get_user_google_account(user.id) do
      nil ->
        {:error, "No Google account connected"}
      account ->
        scopes = account.scopes || []
        if length(scopes) > 0 do
          {:ok, scopes}
        else
          {:ok, ["No scopes found - please reconnect your Google account"]}
        end
    end
  end

  # Extract email information from message
  defp extract_email_info_from_message(message) do
    # Simple extraction - look for email patterns and common phrases
    email_regex = ~r/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/

    case Regex.run(email_regex, message) do
      [email] ->
        # Extract subject from message
        subject = case Regex.run(~r/about\s+(.+?)(?:\s|$)/i, message) do
          [_, subj] -> String.trim(subj)
          _ -> "Meeting"
        end

        # Create body
        body = "Hi,\n\nI wanted to touch base with you about #{subject}.\n\nBest regards"

        {:ok, %{"to" => email, "subject" => subject, "body" => body}}

      _ ->
        {:error, "No email address found"}
    end
  end

  # Extract search query from message
  defp extract_search_query_from_message(message) do
    # Remove common words and extract meaningful search terms
    message_down = String.downcase(message)

    # Remove common words
    cleaned = message_down
    |> String.replace(~r/\b(show|me|my|find|search|get|emails?|email)\b/, "")
    |> String.replace(~r/\b(recent|last|sent|received)\b/, "")
    |> String.trim()

    if cleaned == "" do
      ""  # Empty search for recent emails
    else
      cleaned
    end
  end

  # Extract calendar information from message
  defp extract_calendar_info_from_message(_message) do
    # Simple extraction for now
    {:ok, %{
      "summary" => "Meeting",
      "start_time" => DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601(),
      "end_time" => DateTime.utc_now() |> DateTime.add(7200, :second) |> DateTime.to_iso8601(),
      "description" => "Meeting scheduled from message"
    }}
  end

  # Determine which tool to use based on parameters
  defp determine_tool_from_params(params, _context) do
    cond do
      # Gmail tools
      Map.has_key?(params, "query") and (String.contains?(Map.get(params, "query", ""), "sent") or String.contains?(Map.get(params, "query", ""), "from:") or String.contains?(Map.get(params, "query", ""), "subject:")) ->
        "gmail_list_messages"

      Map.has_key?(params, "message_id") ->
        "gmail_get_message"

      Map.has_key?(params, "to") and Map.has_key?(params, "subject") ->
        "gmail_send_message"

      # Calendar tools
      Map.has_key?(params, "summary") and Map.has_key?(params, "start_time") ->
        "calendar_create_event"

      Map.has_key?(params, "event_id") ->
        "calendar_get_event"

      # Default to gmail_list_messages for general queries
      Map.has_key?(params, "query") ->
        "gmail_list_messages"

      true ->
        nil
    end
  end
end
