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
  defp build_ai_context(user, conversation, user_context) do
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
    base_tools = [
      # Gmail Tools
      %{
        name: "gmail_list_messages",
        description: "List or search emails in Gmail. Use for: showing recent emails, finding emails from someone, searching by subject, etc.",
        parameters: %{
          type: "object",
          properties: %{
            query: %{
              type: "string",
              description: "Gmail search query (e.g., 'from:alice', 'subject:meeting', 'in:sent', 'is:unread')"
            },
            max_results: %{
              type: "integer",
              description: "Maximum number of emails to return (default: 10)"
            },
            label_ids: %{
              type: "array",
              items: %{type: "string"},
              description: "Gmail label IDs to filter by"
            }
          },
          required: []
        }
      },
      %{
        name: "gmail_get_message",
        description: "Get detailed information about a specific email message",
        parameters: %{
          type: "object",
          properties: %{
            message_id: %{
              type: "string",
              description: "Gmail message ID"
            }
          },
          required: ["message_id"]
        }
      },
      %{
        name: "gmail_send_message",
        description: "Send an email through Gmail",
        parameters: %{
          type: "object",
          properties: %{
            to: %{
              type: "string",
              description: "Recipient email address"
            },
            subject: %{
              type: "string",
              description: "Email subject"
            },
            body: %{
              type: "string",
              description: "Email body content"
            },
            cc: %{
              type: "string",
              description: "CC recipients (comma-separated)"
            },
            bcc: %{
              type: "string",
              description: "BCC recipients (comma-separated)"
            }
          },
          required: ["to", "subject", "body"]
        }
      },
      %{
        name: "gmail_delete_message",
        description: "Delete an email message (moves to trash)",
        parameters: %{
          type: "object",
          properties: %{
            message_id: %{
              type: "string",
              description: "Gmail message ID to delete"
            }
          },
          required: ["message_id"]
        }
      },
      %{
        name: "gmail_modify_message",
        description: "Modify email labels (mark as read/unread, add/remove labels)",
        parameters: %{
          type: "object",
          properties: %{
            message_id: %{
              type: "string",
              description: "Gmail message ID"
            },
            add_label_ids: %{
              type: "array",
              items: %{type: "string"},
              description: "Label IDs to add"
            },
            remove_label_ids: %{
              type: "array",
              items: %{type: "string"},
              description: "Label IDs to remove"
            }
          },
          required: ["message_id"]
        }
      },
      %{
        name: "gmail_create_draft",
        description: "Create a draft email (doesn't send immediately)",
        parameters: %{
          type: "object",
          properties: %{
            to: %{
              type: "string",
              description: "Recipient email address"
            },
            subject: %{
              type: "string",
              description: "Email subject"
            },
            body: %{
              type: "string",
              description: "Email body content"
            }
          },
          required: ["to", "subject", "body"]
        }
      },
      %{
        name: "gmail_get_profile",
        description: "Get Gmail profile information (email address, etc.)",
        parameters: %{
          type: "object",
          properties: %{},
          required: []
        }
      },
      # Calendar Tools
      %{
        name: "calendar_list_events",
        description: "List calendar events. Use for: showing upcoming events, finding events on a date, etc.",
        parameters: %{
          type: "object",
          properties: %{
            calendar_id: %{
              type: "string",
              description: "Calendar ID (default: 'primary')"
            },
            time_min: %{
              type: "string",
              description: "Start time for search (ISO 8601 format)"
            },
            time_max: %{
              type: "string",
              description: "End time for search (ISO 8601 format)"
            },
            max_results: %{
              type: "integer",
              description: "Maximum number of events to return"
            },
            q: %{
              type: "string",
              description: "Search query for events"
            }
          },
          required: []
        }
      },
      %{
        name: "calendar_get_event",
        description: "Get detailed information about a specific calendar event",
        parameters: %{
          type: "object",
          properties: %{
            calendar_id: %{
              type: "string",
              description: "Calendar ID (default: 'primary')"
            },
            event_id: %{
              type: "string",
              description: "Event ID"
            }
          },
          required: ["event_id"]
        }
      },
      %{
        name: "calendar_create_event",
        description: "Create a new calendar event",
        parameters: %{
          type: "object",
          properties: %{
            calendar_id: %{
              type: "string",
              description: "Calendar ID (default: 'primary')"
            },
            summary: %{
              type: "string",
              description: "Event title/summary"
            },
            description: %{
              type: "string",
              description: "Event description"
            },
            start_time: %{
              type: "string",
              description: "Start time (ISO 8601 format)"
            },
            end_time: %{
              type: "string",
              description: "End time (ISO 8601 format)"
            },
            attendees: %{
              type: "array",
              items: %{type: "string"},
              description: "List of attendee email addresses"
            },
            location: %{
              type: "string",
              description: "Event location"
            }
          },
          required: ["summary", "start_time", "end_time"]
        }
      },
      %{
        name: "calendar_update_event",
        description: "Update an existing calendar event",
        parameters: %{
          type: "object",
          properties: %{
            calendar_id: %{
              type: "string",
              description: "Calendar ID (default: 'primary')"
            },
            event_id: %{
              type: "string",
              description: "Event ID"
            },
            summary: %{
              type: "string",
              description: "Event title/summary"
            },
            description: %{
              type: "string",
              description: "Event description"
            },
            start_time: %{
              type: "string",
              description: "Start time (ISO 8601 format)"
            },
            end_time: %{
              type: "string",
              description: "End time (ISO 8601 format)"
            },
            attendees: %{
              type: "array",
              items: %{type: "string"},
              description: "List of attendee email addresses"
            },
            location: %{
              type: "string",
              description: "Event location"
            }
          },
          required: ["event_id"]
        }
      },
      %{
        name: "calendar_delete_event",
        description: "Delete a calendar event",
        parameters: %{
          type: "object",
          properties: %{
            calendar_id: %{
              type: "string",
              description: "Calendar ID (default: 'primary')"
            },
            event_id: %{
              type: "string",
              description: "Event ID to delete"
            }
          },
          required: ["event_id"]
        }
      },
      %{
        name: "calendar_get_calendars",
        description: "List available calendars",
        parameters: %{
          type: "object",
          properties: %{},
          required: []
        }
      },
      # Contact Tools
      %{
        name: "contacts_search",
        description: "Search for contacts by name or email",
        parameters: %{
          type: "object",
          properties: %{
            query: %{
              type: "string",
              description: "Search query (name or email)"
            }
          },
          required: ["query"]
        }
      },
      %{
        name: "contacts_create",
        description: "Create a new contact",
        parameters: %{
          type: "object",
          properties: %{
            name: %{
              type: "string",
              description: "Contact name"
            },
            email: %{
              type: "string",
              description: "Contact email"
            },
            phone: %{
              type: "string",
              description: "Contact phone number"
            },
            company: %{
              type: "string",
              description: "Contact company"
            }
          },
          required: ["name", "email"]
        }
      }
    ]

    # Filter tools based on user's available services
    Enum.filter(base_tools, fn tool ->
      cond do
        String.starts_with?(tool.name, "gmail_") -> has_gmail_access?(user)
        String.starts_with?(tool.name, "calendar_") -> has_calendar_access?(user)
        String.starts_with?(tool.name, "contacts_") -> has_valid_google_tokens?(user)
        true -> true
      end
    end)
  end

  # Build AI prompt for universal action understanding
  defp build_universal_prompt(user_message, context, tools) do
    tools_description = Enum.map_join(tools, "\n", fn tool ->
      """
      - #{tool.name}: #{tool.description}
        Parameters: #{Jason.encode!(tool.parameters)}
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
      %{
        type: "function",
        function: %{
          name: tool.name,
          description: tool.description,
          parameters: tool.parameters
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

    case function_name do
      # Gmail Tools
      "gmail_list_messages" -> execute_gmail_list_messages(user, arguments)
      "gmail_get_message" -> execute_gmail_get_message(user, arguments)
      "gmail_send_message" -> execute_gmail_send_message(user, arguments)
      "gmail_delete_message" -> execute_gmail_delete_message(user, arguments)
      "gmail_modify_message" -> execute_gmail_modify_message(user, arguments)
      "gmail_create_draft" -> execute_gmail_create_draft(user, arguments)
      "gmail_get_profile" -> execute_gmail_get_profile(user, arguments)

      # Calendar Tools
      "calendar_list_events" -> execute_calendar_list_events(user, arguments)
      "calendar_get_event" -> execute_calendar_get_event(user, arguments)
      "calendar_create_event" -> execute_calendar_create_event(user, arguments)
      "calendar_update_event" -> execute_calendar_update_event(user, arguments)
      "calendar_delete_event" -> execute_calendar_delete_event(user, arguments)
      "calendar_get_calendars" -> execute_calendar_get_calendars(user, arguments)

      # Contact Tools
      "contacts_search" -> execute_contacts_search(user, arguments)
      "contacts_create" -> execute_contacts_create(user, arguments)

      _ ->
        {:error, "Unknown tool: #{function_name}"}
    end
  end

  # Gmail Tool Executions
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

  # Calendar Tool Executions
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
    calendar_id = Map.get(args, "calendar_id", "primary")

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
          "• #{contact.name} (#{contact.email})"
        end) |> Enum.join("\n")

        {:ok, "Found #{length(contacts)} contacts:\n\n#{contact_list}"}

      {:error, reason} ->
        {:error, "Failed to search contacts: #{reason}"}
    end
  end

  defp execute_contacts_create(user, args) do
    # Note: This would need to be implemented in the GoogleContacts module
    {:ok, "Contact created"}
  end

  # Generate response from tool execution results
  defp generate_response_from_results(user_message, results) do
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

  defp create_agent_response(user, conversation_id, content, response_type) do
    Chat.create_message(conversation_id, %{
      role: "assistant",
      content: content,
      metadata: %{response_type: response_type}
    })
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
  defp force_execute_based_on_message(user, user_message, context) do
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

      # Default to recent emails
      true ->
        execute_tool_call(user, %{"name" => "gmail_list_messages", "arguments" => %{"query" => "", "max_results" => 5}})
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
  defp extract_calendar_info_from_message(message) do
    # Simple extraction for now
    {:ok, %{
      "summary" => "Meeting",
      "start_time" => DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601(),
      "end_time" => DateTime.utc_now() |> DateTime.add(7200, :second) |> DateTime.to_iso8601(),
      "description" => "Meeting scheduled from message"
    }}
  end

  # Determine which tool to use based on parameters
  defp determine_tool_from_params(params, context) do
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
