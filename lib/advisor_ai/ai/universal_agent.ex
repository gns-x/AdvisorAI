defmodule AdvisorAi.AI.UniversalAgent do
  @moduledoc """
  Universal AI Agent that can perform any Gmail/Calendar action based on natural language prompts.
  Uses tool calling to autonomously generate and execute API calls without hard-coded function mappings.
  """

  alias AdvisorAi.{Accounts, Chat, AI}
  alias AdvisorAi.Integrations.{Gmail, Calendar, HubSpot}
  alias AI.{OpenRouterClient, TogetherClient, OllamaClient, AgentInstruction}

  @doc """
  Process any user request and autonomously perform the appropriate Gmail/Calendar actions.
  The AI decides what to do based on the prompt, not predefined function mappings.
  """
  def process_request(user, conversation_id, user_message) do
    # Intercept greetings and respond immediately
    case check_for_greeting(user_message) do
      nil ->
        # Check for ongoing workflow in conversation context
        context = Chat.get_conversation_context(conversation_id)
        workflow_state = Map.get(context, "workflow_state")

        # Check if this is an automation instruction
        case recognize_ongoing_instruction(user_message) do
          {:ok, instruction_data} ->
            # Store the instruction
            store_ongoing_instruction(user, instruction_data)
            # Show confirmation message in chat
            confirmation = build_instruction_confirmation(instruction_data)
            create_agent_response(user, conversation_id, confirmation, "conversation")
          {:error, :not_instruction} ->
            cond do
              workflow_state && workflow_state["active"] ->
                # Resume ongoing workflow
                resume_workflow(user, conversation_id, user_message, workflow_state)
              true ->
                # No ongoing workflow, process as normal request
                process_or_start_workflow(user, conversation_id, user_message)
            end
        end
      greeting_response ->
        create_agent_response(user, conversation_id, greeting_response, "conversation")
    end
  end

  # Resume an ongoing workflow
  defp resume_workflow(user, conversation_id, user_message, workflow_state) do
    updated_state = Map.put(workflow_state, "last_user_message", user_message)
    next_step = get_next_workflow_step(updated_state)
    case execute_workflow_step(user, conversation_id, next_step, updated_state) do
      {:continue, new_state} ->
        # Summarize and present results to user
        summary = summarize_step_result(List.last(new_state["results"]))
        # Store recent request and result in context memory
        context = Chat.get_conversation_context(conversation_id)
        recent_memories = (context["recent_memories"] || []) ++ [%{"request" => user_message, "result" => summary}]
        Chat.update_conversation_context(conversation_id, Map.merge(context, %{"workflow_state" => new_state, "recent_memories" => Enum.take(recent_memories, -10)}))
        # Ask user for update/clarification if needed
        case AI.WorkflowGenerator.next_action_llm(new_state, recent_memories) do
          {:ask_user, question} ->
            create_agent_response(user, conversation_id, question, "conversation")
          {:next_step, _llm_step} ->
            resume_workflow(user, conversation_id, user_message, new_state)
          {:edge_case, edge_case_info} ->
            handle_edge_case(user, conversation_id, edge_case_info, new_state)
          {:done, result} ->
            Chat.update_conversation_context(conversation_id, Map.delete(context, "workflow_state"))
            create_agent_response(user, conversation_id, summarize_final_result(result, recent_memories), "action")
        end
      {:done, result} ->
        context = Chat.get_conversation_context(conversation_id)
        recent_memories = (context["recent_memories"] || []) ++ [%{"request" => user_message, "result" => result}]
        Chat.update_conversation_context(conversation_id, Map.merge(context, %{"recent_memories" => Enum.take(recent_memories, -10), "workflow_state" => nil}))
        create_agent_response(user, conversation_id, summarize_final_result(result, recent_memories), "action")
      _ ->
        context = Chat.get_conversation_context(conversation_id)
        Chat.update_conversation_context(conversation_id, Map.delete(context, "workflow_state"))
        create_agent_response(user, conversation_id, "Workflow error.", "error")
    end
  end

  # Summarize step result for user
  defp summarize_step_result(result) do
    # Use LLM or simple logic to summarize
    "Step completed: #{inspect(result)}"
  end

  # Summarize final result for user
  defp summarize_final_result(result, recent_memories) do
    # Use LLM or simple logic to summarize final outcome, referencing recent steps
    "Workflow complete. Summary: #{inspect(result)}\nRecent steps: #{Enum.map_join(recent_memories, ", ", fn m -> m["request"] end)}"
  end

  # Handle edge cases using LLM/tool calling
  defp handle_edge_case(user, conversation_id, edge_case_info, workflow_state) do
    # Use LLM/tool calling to resolve edge case, then continue workflow
    case AI.WorkflowGenerator.resolve_edge_case(edge_case_info, workflow_state) do
      {:ok, new_state} ->
        resume_workflow(user, conversation_id, workflow_state["last_user_message"], new_state)
      {:done, result} ->
        Chat.update_conversation_context(conversation_id, Map.delete(Chat.get_conversation_context(conversation_id), "workflow_state"))
        create_agent_response(user, conversation_id, result, "action")
      _ ->
        Chat.update_conversation_context(conversation_id, Map.delete(Chat.get_conversation_context(conversation_id), "workflow_state"))
        create_agent_response(user, conversation_id, "Edge case error.", "error")
    end
  end

  # Start a new workflow or process as normal
  defp process_or_start_workflow(user, conversation_id, user_message) do
    # Use WorkflowGenerator to check if this is a complex request
    case AI.WorkflowGenerator.generate_workflow(user_message) do
      {:ok, workflow} ->
        if is_map(workflow) and Map.has_key?(workflow, "steps") and is_list(workflow["steps"]) do
          # Start new workflow state
          workflow_state = %{"active" => true, "workflow" => workflow, "current_step" => 0, "results" => [], "last_user_message" => user_message}
          Chat.update_conversation_context(conversation_id, Map.put(Chat.get_conversation_context(conversation_id), "workflow_state", workflow_state))
          resume_workflow(user, conversation_id, user_message, workflow_state)
        else
          # Not a workflow, process as normal
          process_normal_request(user, conversation_id, user_message)
        end
      _ ->
        # Not a workflow, process as normal
        process_normal_request(user, conversation_id, user_message)
    end
  end

  # Decide next workflow step using LLM and state
  defp get_next_workflow_step(workflow_state) do
    steps = workflow_state["workflow"]["steps"]
    current_step = workflow_state["current_step"] || 0
    if current_step < length(steps) do
      Enum.at(steps, current_step)
    else
      nil
    end
  end

  # Execute a workflow step, update state, and decide if done
  defp execute_workflow_step(user, conversation_id, step, workflow_state) do
    if is_nil(step) do
      {:done, "Workflow complete. All steps executed."}
    else
      action = step["action"]
      params = step["params"] || %{}
      api = step["api"] || "universal_action"
      # Dynamic extraction for contact name/email and times
      extracted_data = workflow_state["results"] || []
      # For steps that need contact info, extract from previous steps or user message
      params =
        params
        |> Map.new(fn {k, v} ->
          case v do
            "extracted_name_or_email" ->
              {k, extract_contact_name_or_email(user, conversation_id, workflow_state)}
            "contact_email" ->
              {k, extract_contact_email_from_results(extracted_data)}
            "contact_name" ->
              {k, extract_contact_name_from_results(extracted_data)}
            "available_times" ->
              {k, extract_available_times_from_results(extracted_data)}
            "chosen_time" ->
              {k, extract_chosen_time_from_results(extracted_data)}
            _ -> {k, v}
          end
        end)
      tool_call = %{"name" => api, "arguments" => Map.put(params, "action", action)}
      result = execute_tool_call(user, tool_call)
      # If the step is 'wait_for_reply', pause workflow and wait for user/contact reply
      if action == "wait_for_reply" do
        {:done, "Waiting for reply from contact. Please respond to continue the workflow."}
      else
        # Update workflow state
        new_results = (workflow_state["results"] || []) ++ [result]
        new_state = workflow_state
          |> Map.put("current_step", (workflow_state["current_step"] || 0) + 1)
          |> Map.put("results", new_results)
        if new_state["current_step"] < length(workflow_state["workflow"]["steps"]) do
          {:continue, new_state}
        else
          {:done, "Workflow complete. Results: #{inspect(new_results)}"}
        end
      end
    end
  end

  # Helper functions for dynamic extraction
  defp extract_contact_name_or_email(user, conversation_id, workflow_state) do
    # Try to extract from user message or previous results
    context = Chat.get_conversation_context(conversation_id)
    user_message = workflow_state["last_user_message"] || ""
    name = AdvisorAi.AI.Agent.extract_name(user_message)
    email = AdvisorAi.AI.Agent.extract_email_address(user_message)
    email || name || ""
  end

  defp extract_contact_email_from_results(results) do
    # Look for an email in previous step results
    results
    |> Enum.find_value(fn
      {:ok, %{"email" => email}} -> email
      {:ok, email} when is_binary(email) -> email
      _ -> nil
    end) || ""
  end

  defp extract_contact_name_from_results(results) do
    results
    |> Enum.find_value(fn
      {:ok, %{"name" => name}} -> name
      {:ok, name} when is_binary(name) -> name
      _ -> nil
    end) || ""
  end

  defp extract_available_times_from_results(results) do
    # Find available times from calendar step
    results
    |> Enum.find_value(fn
      {:ok, times} when is_list(times) -> Enum.join(times, ", ")
      {:ok, %{"available_times" => times}} -> times
      _ -> nil
    end) || ""
  end

  defp extract_chosen_time_from_results(results) do
    # Find chosen time from reply analysis (could be enhanced with LLM)
    results
    |> Enum.find_value(fn
      {:ok, %{"chosen_time" => time}} -> time
      {:ok, time} when is_binary(time) -> time
      _ -> nil
    end) || ""
  end

  # Process normal requests (non-instruction requests)
  defp process_normal_request(user, conversation_id, user_message) do
    conversation = get_conversation_with_context(conversation_id, user.id)
    user_context = get_comprehensive_user_context(user)

    # Build context for AI
    context = build_ai_context(user, conversation, user_context)

    # Get available tools (Gmail/Calendar API capabilities)
    tools = get_available_tools(user)

    # If no tools are available, provide a helpful response
    if Enum.empty?(tools) do
      create_agent_response(
        user,
        conversation_id,
        "I'd be happy to help you with that! However, I need you to connect your accounts first so I can access your real data. Please go to Settings > Integrations to connect your Gmail, Google Calendar, or HubSpot accounts. Once connected, I'll be able to search your emails, manage your calendar, and access your contacts.",
        "conversation"
      )
    else
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

          create_agent_response(
            user,
            conversation_id,
            "I'm having trouble understanding your request. Please try rephrasing it.",
            "error"
          )
      end
    end
  end

  # Check for common greetings and return appropriate response
  defp check_for_greeting(message) do
    message_lower = String.downcase(String.trim(message))

    cond do
      message_lower in [
        "hello",
        "hi",
        "hey",
        "good morning",
        "good afternoon",
        "good evening",
        "greetings"
      ] ->
        "Hello! I'm your AI assistant. I can help you with emails, calendar management, and contact searches. What would you like to do today?"

      message_lower in ["how are you", "how are you doing", "how's it going"] ->
        "I'm doing well, thank you for asking! I'm ready to help you manage your emails, calendar, and HubSpot contacts. What can I assist you with?"

      message_lower in ["thanks", "thank you", "thx", "ty"] ->
        "You're welcome! Is there anything else I can help you with?"

      message_lower in ["bye", "goodbye", "see you", "see ya"] ->
        "Goodbye! Feel free to reach out if you need any help later."

      true ->
        nil
    end
  end

  # Build comprehensive context for AI
  def build_ai_context(user, conversation, _user_context) do
    %{
      user: %{
        name: user.name || "User",
        email: user.email,
        google_connected: has_valid_google_tokens?(user),
        gmail_available: has_gmail_access?(user),
        calendar_available: has_calendar_access?(user),
        hubspot_connected: has_hubspot_connection?(user)
      },
      conversation: get_conversation_summary(conversation),
      recent_messages: get_recent_messages(conversation),
      current_time: DateTime.utc_now()
    }
  end

  # Get all available Gmail/Calendar tools as a schema
  def get_available_tools(user) do
    # Check what services are available
    google_connected = has_valid_google_tokens?(user)
    gmail_available = has_gmail_access?(user)
    calendar_available = has_calendar_access?(user)
    hubspot_connected = has_hubspot_connection?(user)

    # Only return tools if user has access to at least one service
    if google_connected or gmail_available or calendar_available or hubspot_connected do
      [
        # Universal Action Tool - Handles ANY request dynamically
        %{
          name: "universal_action",
          description:
            "Execute any action related to Gmail, Calendar, HubSpot, or OAuth. This is a flexible tool that can handle any request by interpreting the action name and parameters. Examples: search emails, send email, list events, create event, search contacts, check permissions, etc.",
          parameters: %{
            type: "object",
            properties: %{
              action: %{
                type: "string",
                description:
                  "The action to perform (e.g., 'search_emails', 'send_email', 'list_events', 'create_event', 'search_contacts', 'check_permissions', 'delete_email', 'update_event', etc.)"
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
    tools_description =
      if Enum.empty?(tools) do
        "No tools available - user has not connected any services (Gmail, Calendar, HubSpot)"
      else
        Enum.map_join(tools, "\n", fn tool ->
          {name, description, parameters} =
            case tool do
              %{function: %{name: n, description: d, parameters: p}} -> {n, d, p}
              %{name: n, description: d, parameters: p} -> {n, d, p}
              _ -> {"unknown", "No description", %{}}
            end

          """
          - #{name}: #{description}
            Parameters: #{Jason.encode!(parameters)}
          """
        end)
      end

    # Determine what services are available
    services_available = cond do
      context.user.google_connected and context.user.gmail_available and context.user.calendar_available and context.user.hubspot_connected ->
        "Gmail, Google Calendar, and HubSpot CRM"
      context.user.google_connected and context.user.gmail_available and context.user.hubspot_connected ->
        "Gmail and HubSpot CRM"
      context.user.google_connected and context.user.calendar_available and context.user.hubspot_connected ->
        "Google Calendar and HubSpot CRM"
      context.user.google_connected and context.user.gmail_available ->
        "Gmail and HubSpot CRM"
      context.user.google_connected and context.user.calendar_available ->
        "Google Calendar and HubSpot CRM"
      context.user.hubspot_connected ->
        "HubSpot CRM only"
      context.user.google_connected ->
        "HubSpot CRM only"
      true ->
        "No services connected"
    end

    """
    You are an advanced AI assistant for financial advisors. You have access to: #{services_available}

    ## CRITICAL INSTRUCTIONS - YOU MUST USE TOOL CALLS:
    - NEVER generate fake data or pretend to perform actions
    - ALWAYS use the available tools to perform real actions
    - If you need to send an email, use the universal_action tool with action "send_email"
    - If you need to create a calendar event, use the universal_action tool with action "create_event"
    - If you need to search contacts, use the universal_action tool with action "search_contacts"
    - If the user asks for their meetings, events, or calendar, ALWAYS use the universal_action tool with action "list_events" or "get_events" (Google Calendar). Do NOT use HubSpot contacts for meetings or events.
    - For queries like 'my meetings today', 'show my events', 'what meetings do I have', 'calendar for today', ALWAYS use Google Calendar first.
    - DO NOT write fake responses like "Email sent successfully" - actually call the tools
    - If no services are connected, clearly state that you need the user to connect their accounts first

    ## Available Tools:
    #{if Enum.empty?(tools), do: "- No tools available - user needs to connect services first", else: "- universal_action: Execute any Gmail, Calendar, or HubSpot action"}

    ## Tool Usage Examples:
    - To send an email: Use universal_action with action="send_email", to="recipient@email.com", subject="Subject", body="Email body"
    - To create calendar event: Use universal_action with action="create_event", summary="Event title", start_time="2025-07-07T10:00:00Z", end_time="2025-07-07T11:00:00Z"
    - To list today's meetings: Use universal_action with action="list_events", date="2025-07-07"
    - To get all meetings today: Use universal_action with action="get_events", date="2025-07-07"
    - To search contacts: Use universal_action with action="search_contacts", query="search term"
    - To get calendar for today: Use universal_action with action="list_events", date="2025-07-07"

    ## Current User Context:
    - Name: #{context.user.name}
    - Email: #{context.user.email}
    - Google Connected: #{context.user.google_connected}
    - Gmail Available: #{context.user.gmail_available}
    - Calendar Available: #{context.user.calendar_available}
    - HubSpot Connected: #{context.user.hubspot_connected}
    - Current Time: #{context.current_time}

    ## User Request: \"#{user_message}\"

    IMPORTANT: You MUST use the universal_action tool to perform the requested action. Do NOT generate fake responses or pretend to perform actions. Use the tool with the appropriate action and parameters.

    For the user's request \"#{user_message}\", you MUST:
    1. Determine what action is needed (send_email, create_event, list_events, get_events, search_contacts, etc.)
    2. For meetings/events/calendar requests, ALWAYS use Google Calendar first.
    3. Use the universal_action tool with the correct action and parameters
    4. Return only the tool call result, not a fake response
    """
  end

  # Get AI response with tool calls using OpenRouter (supports function calling)
  defp get_ai_response_with_tools(prompt, tools) do
    # Convert tools to OpenRouter tool calling format (newer format)
    tools_format =
      Enum.map(tools, fn tool ->
        {name, description, parameters} =
          case tool do
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
      %{
        "role" => "system",
        "content" =>
          "You are an advanced AI assistant for financial advisors with access to Gmail, Google Calendar, and HubSpot CRM. CRITICAL: You MUST use the provided tools to perform actions. NEVER generate fake responses or pretend to perform actions. Always use tool calls for any email, calendar, or contact operations. If you cannot perform an action with the available tools, clearly state what tools are needed. IMPORTANT: When the user asks you to perform an action, you MUST use the universal_action tool with the appropriate action and parameters. Do NOT write fake responses like 'Email sent successfully' - actually call the tools."
      },
      %{"role" => "user", "content" => prompt}
    ]

    case OpenRouterClient.chat_completion(
           messages: messages,
           tools: tools_format,
           tool_choice: "auto",
           temperature: 0.1
         ) do
      {:ok, response} ->
        {:ok, response}

      {:error, _} ->
        # Fallback to Together AI
        case TogetherClient.chat_completion(
               messages: messages,
               tools: tools_format,
               tool_choice: "auto",
               temperature: 0.1
             ) do
          {:ok, response} ->
            {:ok, response}

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
    IO.puts("DEBUG: Parsing tool calls from AI response...")
    case parse_tool_calls(ai_response) do
      {:ok, tool_calls} when tool_calls != [] ->
        IO.puts("DEBUG: Tool calls found: #{inspect(tool_calls)}")
        # Execute each tool call
        results =
          Enum.map(tool_calls, fn tool_call ->
            IO.puts("DEBUG: Executing tool call: #{inspect(tool_call)}")
            execute_tool_call(user, tool_call)
          end)

        # Only show the actual result(s), not the plan or tool call JSON
        response_text =
          results
          |> Enum.map(fn
            {:ok, result} -> result
            {:error, error} -> "Error: #{error}"
            {:ask_user, prompt} -> prompt
            {:ask_user, prompt, _extra} -> prompt
            other when is_binary(other) -> other
            other -> inspect(other)
          end)
          |> Enum.join("\n\n")

        create_agent_response(user, conversation_id, response_text, "action")

      {:ok, []} ->
        # No tool calls found, check if this is a fake response
        response_text = extract_text_response(ai_response)
        IO.puts("DEBUG: No tool calls found. Response text: #{inspect(response_text)}")
        # Always try to extract and execute tool calls from the text, even if not marked as fake
        case extract_bash_style_tool_calls(response_text) do
          {:ok, tool_calls} when tool_calls != [] ->
            IO.puts("DEBUG: Extracted bash-style tool calls (even if not fake): #{inspect(tool_calls)}")
            results =
              Enum.map(tool_calls, fn tool_call ->
                IO.puts("DEBUG: Executing extracted tool call: #{inspect(tool_call)}")
                execute_tool_call(user, tool_call)
              end)
            response_text =
              results
              |> Enum.map(fn
                {:ok, result} -> result
                {:error, error} -> "Error: #{error}"
                {:ask_user, prompt} -> prompt
                {:ask_user, prompt, _extra} -> prompt
                other when is_binary(other) -> other
                other -> inspect(other)
              end)
              |> Enum.join("\n\n")
            create_agent_response(user, conversation_id, response_text, "action")
          _ ->
            # Only return a conversation if there is no tool call pattern in the text
            if Regex.match?(~r/universal_action\s*\(/, response_text) or Regex.match?(~r/universal_action\s+action=/, response_text) do
              IO.puts("DEBUG: Tool call pattern found in text but not parsed. Forcing extraction and execution.")
              # Try to extract and execute again (should not happen, but fallback)
              case extract_bash_style_tool_calls(response_text) do
                {:ok, tool_calls} when tool_calls != [] ->
                  IO.puts("DEBUG: Fallback extracted tool calls: #{inspect(tool_calls)}")
                  results =
                    Enum.map(tool_calls, fn tool_call ->
                      IO.puts("DEBUG: Executing fallback tool call: #{inspect(tool_call)}")
                      execute_tool_call(user, tool_call)
                    end)
                  response_text =
                    results
                    |> Enum.map(fn
                      {:ok, result} -> result
                      {:error, error} -> "Error: #{error}"
                      {:ask_user, prompt} -> prompt
                      {:ask_user, prompt, _extra} -> prompt
                      other when is_binary(other) -> other
                      other -> inspect(other)
                    end)
                    |> Enum.join("\n\n")
                  create_agent_response(user, conversation_id, response_text, "action")
                _ ->
                  IO.puts("DEBUG: No tool call could be extracted from pattern. Returning error.")
                  create_agent_response(user, conversation_id, "Sorry, I could not execute your request. Please try again.", "error")
              end
            else
              if is_fake_response?(response_text) do
                # Try to extract and execute bash-style tool calls from the fake response (legacy)
                case extract_bash_style_tool_calls(response_text) do
                  {:ok, tool_calls} when tool_calls != [] ->
                    IO.puts("DEBUG: Extracted bash-style tool calls: #{inspect(tool_calls)}")
                    # Execute the extracted tool calls
                    results =
                      Enum.map(tool_calls, fn tool_call ->
                        IO.puts("DEBUG: Executing extracted tool call: #{inspect(tool_call)}")
                        execute_tool_call(user, tool_call)
                      end)
                    response_text =
                      results
                      |> Enum.map(fn
                        {:ok, result} -> result
                        {:error, error} -> "Error: #{error}"
                        {:ask_user, prompt} -> prompt
                        {:ask_user, prompt, _extra} -> prompt
                        other when is_binary(other) -> other
                        other -> inspect(other)
                      end)
                      |> Enum.join("\n\n")
                    create_agent_response(user, conversation_id, response_text, "action")
                  _ ->
                    # Force the AI to use tools by retrying with a more explicit prompt
                    IO.puts("DEBUG: Forcing tool usage with explicit prompt...")
                    force_tool_usage(user, conversation_id, user_message, context)
                end
              else
                # Try to extract JSON from the AI's text response
                case extract_and_execute_json_from_text(user, response_text, context) do
                  {:ok, result} ->
                    create_agent_response(user, conversation_id, result, "action")
                  {:error, _} ->
                    # If no JSON found, just return the LLM's conversational response
                    create_agent_response(
                      user,
                      conversation_id,
                      response_text || "I'm not sure how to help with that yet, but I'm learning!",
                      "conversation"
                    )
                end
              end
            end
        end

      {:error, reason} ->
        IO.puts("Failed to parse tool calls: #{reason}")
        response_text = extract_text_response(ai_response)
        # Always try to extract and execute tool calls from the text, even if not marked as fake
        case extract_bash_style_tool_calls(response_text) do
          {:ok, tool_calls} when tool_calls != [] ->
            IO.puts("DEBUG: Extracted bash-style tool calls (even if not fake): #{inspect(tool_calls)}")
            results =
              Enum.map(tool_calls, fn tool_call ->
                IO.puts("DEBUG: Executing extracted tool call: #{inspect(tool_call)}")
                execute_tool_call(user, tool_call)
              end)
            response_text =
              results
              |> Enum.map(fn
                {:ok, result} -> result
                {:error, error} -> "Error: #{error}"
                {:ask_user, prompt} -> prompt
                {:ask_user, prompt, _extra} -> prompt
                other when is_binary(other) -> other
                other -> inspect(other)
              end)
              |> Enum.join("\n\n")
            create_agent_response(user, conversation_id, response_text, "action")
          _ ->
            if is_fake_response?(response_text) do
              # Try to extract and execute bash-style tool calls from the fake response (legacy)
              case extract_bash_style_tool_calls(response_text) do
                {:ok, tool_calls} when tool_calls != [] ->
                  IO.puts("DEBUG: Extracted bash-style tool calls: #{inspect(tool_calls)}")
                  # Execute the extracted tool calls
                  results =
                    Enum.map(tool_calls, fn tool_call ->
                      IO.puts("DEBUG: Executing extracted tool call: #{inspect(tool_call)}")
                      execute_tool_call(user, tool_call)
                    end)
                  response_text =
                    results
                    |> Enum.map(fn
                      {:ok, result} -> result
                      {:error, error} -> "Error: #{error}"
                      {:ask_user, prompt} -> prompt
                      {:ask_user, prompt, _extra} -> prompt
                      other when is_binary(other) -> other
                      other -> inspect(other)
                    end)
                    |> Enum.join("\n\n")
                  create_agent_response(user, conversation_id, response_text, "action")
                _ ->
                  IO.puts("DEBUG: Forcing tool usage with explicit prompt...")
                  force_tool_usage(user, conversation_id, user_message, context)
              end
            else
              case extract_and_execute_json_from_text(user, response_text, context) do
                {:ok, result} ->
                  create_agent_response(user, conversation_id, result, "action")
                {:error, _} ->
                  # If no JSON found, just return the LLM's conversational response
                  create_agent_response(
                    user,
                    conversation_id,
                    response_text || "I'm not sure how to help with that yet, but I'm learning!",
                    "conversation"
                  )
              end
            end
        end
    end
  end

  # Detect if the AI generated a fake response instead of using tools
  defp is_fake_response?(response_text) do
    if is_nil(response_text) do
      false
    else
      fake_indicators = [
        "To fulfill the user's request",
        "Here are the steps:",
        "Here are the tool calls:",
        "```bash",
        "universal_action action=",
        "Please note that I need",
        "If it's not connected",
        "Also, if you want me to",
        "Email sent successfully",
        "Email has been sent",
        "Calendar event created",
        "Event added to calendar",
        "Meeting scheduled",
        "Contact created",
        "HubSpot CRM Updated",
        "Execution Result:",
        "Confirmation:",
        "The email has been sent",
        "The meeting has been scheduled"
      ]

      response_lower = String.downcase(response_text)
      Enum.any?(fake_indicators, fn indicator ->
        String.contains?(response_lower, String.downcase(indicator))
      end)
    end
  end

  # Force the AI to use tools by retrying with a more explicit prompt
  defp force_tool_usage(user, conversation_id, user_message, context) do
    tools = get_available_tools(user)

    if Enum.empty?(tools) do
      create_agent_response(
        user,
        conversation_id,
        "I need you to connect your accounts first so I can perform real actions. Please go to Settings > Integrations to connect your Gmail, Google Calendar, or HubSpot accounts.",
        "error"
      )
    else
      # Create a more explicit prompt that forces tool usage
      explicit_prompt = """
      CRITICAL: You MUST use the available tools to perform the requested action. Do NOT generate fake responses.

      User Request: "#{user_message}"

      Available Tools:
      - universal_action: Execute any Gmail, Calendar, or HubSpot action

      You MUST use the universal_action tool with the appropriate action and parameters.
      For sending emails: action="send_email", to="email", subject="subject", body="body"
      For creating events: action="create_event", summary="title", start_time="time", end_time="time"

      Use the tool now to perform the requested action.
      """

      messages = [
        %{
          "role" => "system",
          "content" => "You are an AI assistant that MUST use tools to perform actions. NEVER generate fake responses. Always use the provided tools."
        },
        %{"role" => "user", "content" => explicit_prompt}
      ]

      tools_format =
        Enum.map(tools, fn tool ->
          {name, description, parameters} =
            case tool do
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

      case OpenRouterClient.chat_completion(
             messages: messages,
             tools: tools_format,
             tool_choice: "auto",
             temperature: 0.1
           ) do
        {:ok, ai_response} ->
          # Try to parse and execute tool calls again
          case parse_tool_calls(ai_response) do
            {:ok, tool_calls} when tool_calls != [] ->
              results =
                Enum.map(tool_calls, fn tool_call ->
                  execute_tool_call(user, tool_call)
                end)

              response_text =
                results
                |> Enum.map(fn
                  {:ok, result} -> result
                  {:error, error} -> "Error: #{error}"
                  {:ask_user, prompt} -> prompt
                  {:ask_user, prompt, _extra} -> prompt
                  other when is_binary(other) -> other
                  other -> inspect(other)
                end)
                |> Enum.join("\n\n")

              create_agent_response(user, conversation_id, response_text, "action")

            _ ->
              create_agent_response(
                user,
                conversation_id,
                "I'm having trouble performing the requested action. Please check that your accounts are properly connected and try again.",
                "error"
              )
          end

        {:error, _} ->
          create_agent_response(
            user,
            conversation_id,
            "I'm having trouble performing the requested action. Please check that your accounts are properly connected and try again.",
            "error"
          )
      end
    end
  end

  # Parse tool calls from AI response
  defp parse_tool_calls(response) do
    case response do
      %{"choices" => [%{"message" => %{"tool_calls" => tool_calls}} | _]} ->
        # Convert tool calls to function call format for compatibility
        function_calls =
          Enum.map(tool_calls, fn tool_call ->
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
    # First try to extract JSON function calls
    case Regex.run(~r/\{\s*"name":\s*"([^"]+)",\s*"arguments":\s*(\{[^}]+\})/, content) do
      [_, name, args_json] ->
        case Jason.decode(args_json) do
          {:ok, args} -> {:ok, [%{"name" => name, "arguments" => args}]}
          {:error, _} -> {:error, "Invalid arguments JSON"}
        end

      _ ->
        # Try to extract bash-style tool calls like: universal_action action="send_email" to="email" subject="subject"
        case extract_bash_style_tool_calls(content) do
          {:ok, calls} -> {:ok, calls}
          {:error, _} -> {:error, "No function calls found"}
        end
    end
  end

  # Extract bash-style tool calls from content
  defp extract_bash_style_tool_calls(content) do
    # Support:
    # universal_action action="search_contacts" query="..."
    # universal_action(action="search_contacts", query="...")
    # universal_action --action=search_contacts --query="..."

    # Pattern 1: universal_action action="..." ...
    tool_call_pattern1 = ~r/universal_action\s+action="([^"]+)"([^`]*?)(?=\n|$|universal_action|```)/

    # Pattern 2: universal_action(action="...", ...)
    tool_call_pattern2 = ~r/universal_action\(([^)]*)\)/

    # Pattern 3: universal_action --action=... --param=value ...
    tool_call_pattern3 = ~r/universal_action\s+((?:--\w+=\"[^\"]*\"|--\w+=\S+)+)/

    tool_calls = []

    # Match pattern 1
    matches1 = Regex.scan(tool_call_pattern1, content)
    tool_calls1 = Enum.map(matches1, fn [_, action, params_string] ->
      args = %{"action" => action}
      param_pattern = ~r/(\w+)="([^"]*)"/
      params = Regex.scan(param_pattern, params_string)
      args = Enum.reduce(params, args, fn [_, key, value], acc -> Map.put(acc, key, value) end)
      %{"name" => "universal_action", "arguments" => args}
    end)

    # Match pattern 2
    matches2 = Regex.scan(tool_call_pattern2, content)
    tool_calls2 = Enum.map(matches2, fn [_, params_string] ->
      # params_string is like: action="search_contacts", query="Hamza Hadioui"
      param_pattern = ~r/(\w+)="([^"]*)"/
      params = Regex.scan(param_pattern, params_string)
      args = Enum.reduce(params, %{}, fn [_, key, value], acc -> Map.put(acc, key, value) end)
      %{"name" => "universal_action", "arguments" => args}
    end)

    # Match pattern 3
    matches3 = Regex.scan(tool_call_pattern3, content)
    tool_calls3 = Enum.map(matches3, fn [_, params_string] ->
      # params_string is like: --action=list_events --date="2025-07-07"
      param_pattern = ~r/--(\w+)=((?:"[^"]*")|(?:\S+))/
      params = Regex.scan(param_pattern, params_string)
      args = Enum.reduce(params, %{}, fn [_, key, value], acc ->
        # Remove quotes if present, but only if value is a binary
        clean_value =
          if is_binary(value) and String.starts_with?(value, "\"") and String.ends_with?(value, "\"") do
            String.slice(value, 1..-2)
          else
            value
          end
        Map.put(acc, key, clean_value)
      end)
      %{"name" => "universal_action", "arguments" => args}
    end)

    all_tool_calls = tool_calls1 ++ tool_calls2 ++ tool_calls3

    if all_tool_calls == [] do
      {:error, "No bash-style tool calls found"}
    else
      {:ok, all_tool_calls}
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
    arguments =
      case raw_arguments do
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
      String.contains?(action_lower, "search") and
          (String.contains?(action_lower, "email") or String.contains?(action_lower, "mail")) ->
        query = Map.get(args, "query", "")
        max_results = Map.get(args, "max_results", 10)
        execute_gmail_action(user, "search", %{query: query, max_results: max_results})

      String.contains?(action_lower, "send") and
          (String.contains?(action_lower, "email") or String.contains?(action_lower, "mail")) ->
        execute_gmail_action(user, "send", args)

      String.contains?(action_lower, "list") and
          (String.contains?(action_lower, "email") or String.contains?(action_lower, "mail")) ->
        execute_gmail_action(user, "list", args)

      String.contains?(action_lower, "delete") and
          (String.contains?(action_lower, "email") or String.contains?(action_lower, "mail")) ->
        execute_gmail_action(user, "delete", args)

      # Calendar actions
      String.contains?(action_lower, "list") and
          (String.contains?(action_lower, "event") or String.contains?(action_lower, "calendar")) ->
        execute_calendar_action(user, "list", args)

      String.contains?(action_lower, "create") and
          (String.contains?(action_lower, "event") or String.contains?(action_lower, "calendar")) ->
        execute_calendar_action(user, "create", args)

      String.contains?(action_lower, "update") and
          (String.contains?(action_lower, "event") or String.contains?(action_lower, "calendar")) ->
        execute_calendar_action(user, "update", args)

      String.contains?(action_lower, "delete") and
          (String.contains?(action_lower, "event") or String.contains?(action_lower, "calendar")) ->
        execute_calendar_action(user, "delete", args)

      # Contact actions
      String.contains?(action_lower, "search") and String.contains?(action_lower, "contact") ->
        execute_contact_action(user, "search", args)

      String.contains?(action_lower, "create") and String.contains?(action_lower, "contact") ->
        execute_contact_action(user, "create", args)

      # OAuth actions
      String.contains?(action_lower, "check") and
          (String.contains?(action_lower, "permission") or String.contains?(action_lower, "scope") or
             String.contains?(action_lower, "oauth")) ->
        execute_oauth_action(user, args)

      # Instruction management actions
      (String.contains?(action_lower, "check") and String.contains?(action_lower, "ongoing") and
          String.contains?(action_lower, "instruction")) or String.contains?(action_lower, "search_instructions") or
          String.contains?(action_lower, "search_ongoing_instructions") or String.contains?(action_lower, "search_memory") ->
        execute_check_ongoing_instructions(user, args)

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

            email_list =
              Enum.map(emails_to_show, fn email ->
                "• #{email.subject} (from: #{email.from})"
              end)
              |> Enum.join("\n")

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

            email_list =
              Enum.map(emails_to_show, fn email ->
                "• #{email.subject} (from: #{email.from})"
              end)
              |> Enum.join("\n")

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

  defp execute_calendar_action(user, action, args) do
    case action do
      "create" ->
        # Fix: resolve attendees if it's a nested tool call
        attendees = Map.get(args, "attendees", [])

        resolved_attendees =
          cond do
            is_map(attendees) and Map.has_key?(attendees, "function_name") and
                Map.has_key?(attendees, "args") ->
              # Execute the nested tool call to get contacts
              tool_call = %{
                "name" => attendees["function_name"],
                "arguments" => Enum.at(attendees["args"], 0)
              }

              case execute_tool_call(user, tool_call) do
                {:ok, contacts_result} ->
                  # contacts_result is a string like "Found 1 contacts:\n\n• Name (email) - phone"
                  # Extract emails from the result
                  Regex.scan(~r/\(([^)]+@[^)]+)\)/, contacts_result)
                  |> Enum.map(fn [_, email] -> email end)

                _ ->
                  []
              end

            is_list(attendees) ->
              attendees

            true ->
              []
          end

        event_data = Map.put(args, "attendees", resolved_attendees)
        case Calendar.create_event(user, event_data) do
          {:ok, created_event} ->
            summary = created_event["summary"] || "(No title)"
            start_time = get_in(created_event, ["start", "dateTime"]) || get_in(created_event, ["start", "date"]) || "(No start time)"
            end_time = get_in(created_event, ["end", "dateTime"]) || get_in(created_event, ["end", "date"]) || "(No end time)"
            attendees = (created_event["attendees"] || []) |> Enum.map(fn a -> a["email"] end) |> Enum.join(", ")

            # Format times for readability (show local time if possible)
            formatted_start = format_datetime_for_chat(start_time)
            formatted_end = format_datetime_for_chat(end_time)

            response =
              "✅ Appointment scheduled!\n" <>
              "Title: #{summary}\n" <>
              "Start: #{formatted_start}\n" <>
              "End:   #{formatted_end}" <>
              (if attendees != "", do: "\nAttendees: #{attendees}", else: "")

            {:ok, response}
          {:error, reason} ->
            {:error, reason}
        end
      "list" ->
        case Calendar.list_events(user) do
          {:ok, events} when is_list(events) ->
            if length(events) > 0 do
              event_list =
                Enum.map(events, fn event ->
                  start_time =
                    get_in(event, ["start", "dateTime"]) || get_in(event, ["start", "date"])

                  "• #{event["summary"]} (#{start_time})"
                end)
                |> Enum.join("\n")

              {:ok, "Found #{length(events)} events:\n\n#{event_list}"}
            else
              {:ok, "No events found"}
            end

          {:ok, other} ->
            {:ok, inspect(other)}

          {:error, reason} ->
            {:error, "Failed to list events: #{reason}"}
        end
      _ ->
        {:error, "Unknown calendar action: #{action}"}
    end
  end

  defp execute_contact_action(user, operation, args) do
    case operation do
      "search" ->
        query = Map.get(args, "query") || Map.get(args, :query) || ""

        if is_binary(query) and String.trim(query) == "" do
          # No query provided, list all contacts
          case HubSpot.list_contacts(user, 50) do
            {:ok, contacts} when is_list(contacts) and length(contacts) > 0 ->
              contact_list =
                Enum.map(contacts, fn contact ->
                  properties = contact["properties"] || %{}
                  firstname = properties["firstname"] || ""
                  lastname = properties["lastname"] || ""
                  email = properties["email"] || ""
                  company = properties["company"] || ""
                  phone = properties["phone"] || ""
                  jobtitle = properties["jobtitle"] || ""

                  name = "#{firstname} #{lastname}" |> String.trim()
                  name = if name == "", do: "Unknown", else: name

                  contact_info = "• #{name}"
                  contact_info = if email != "", do: contact_info <> " (#{email})", else: contact_info
                  contact_info = if company != "", do: contact_info <> " - #{company}", else: contact_info
                  contact_info = if jobtitle != "", do: contact_info <> " (#{jobtitle})", else: contact_info
                  contact_info = if phone != "", do: contact_info <> " - #{phone}", else: contact_info
                  contact_info
                end)
                |> Enum.join("\n")

              {:ok, "Found #{length(contacts)} HubSpot contacts:\n\n#{contact_list}"}
            {:ok, _} ->
              {:ok, "No contacts were found in your HubSpot account. You can add new contacts in HubSpot or try a different search."}
            {:error, reason} ->
              {:error, "Failed to list HubSpot contacts: #{reason}"}
          end
        else
          # Query provided, use search_contacts
          case HubSpot.search_contacts(user, query) do
            {:ok, contacts} when is_list(contacts) and length(contacts) > 0 ->
              contact_list =
                Enum.map(contacts, fn contact ->
                  properties = contact["properties"] || %{}
                  firstname = properties["firstname"] || ""
                  lastname = properties["lastname"] || ""
                  email = properties["email"] || ""
                  company = properties["company"] || ""
                  phone = properties["phone"] || ""
                  jobtitle = properties["jobtitle"] || ""

                  name = "#{firstname} #{lastname}" |> String.trim()
                  name = if name == "", do: "Unknown", else: name

                  contact_info = "• #{name}"
                  contact_info = if email != "", do: contact_info <> " (#{email})", else: contact_info
                  contact_info = if company != "", do: contact_info <> " - #{company}", else: contact_info
                  contact_info = if jobtitle != "", do: contact_info <> " (#{jobtitle})", else: contact_info
                  contact_info = if phone != "", do: contact_info <> " - #{phone}", else: contact_info
                  contact_info
                end)
                |> Enum.join("\n")

              {:ok, "Found #{length(contacts)} HubSpot contacts:\n\n#{contact_list}"}
            {:ok, _} ->
              {:ok, "No contacts were found in your HubSpot account. You can add new contacts in HubSpot or try a different search."}
            {:error, reason} ->
              {:error, "Failed to search HubSpot contacts: #{reason}"}
          end
        end

      "list" ->
        limit = Map.get(args, "limit") || Map.get(args, :limit) || 50

        case HubSpot.list_contacts(user, limit) do
          {:ok, contacts} when is_list(contacts) and length(contacts) > 0 ->
            contact_list =
              Enum.map(contacts, fn contact ->
                properties = contact["properties"] || %{}
                firstname = properties["firstname"] || ""
                lastname = properties["lastname"] || ""
                email = properties["email"] || ""
                company = properties["company"] || ""
                phone = properties["phone"] || ""
                jobtitle = properties["jobtitle"] || ""

                name = "#{firstname} #{lastname}" |> String.trim()
                name = if name == "", do: "Unknown", else: name

                contact_info = "• #{name}"

                contact_info =
                  if email != "", do: contact_info <> " (#{email})", else: contact_info

                contact_info =
                  if company != "", do: contact_info <> " - #{company}", else: contact_info

                contact_info =
                  if jobtitle != "", do: contact_info <> " (#{jobtitle})", else: contact_info

                contact_info =
                  if phone != "", do: contact_info <> " - #{phone}", else: contact_info

                contact_info
              end)
              |> Enum.join("\n")

            {:ok, "Found #{length(contacts)} HubSpot contacts:\n\n#{contact_list}"}

          {:ok, _} ->
            {:ok, "No HubSpot contacts found."}

          {:error, reason} ->
            {:error, "Failed to list HubSpot contacts: #{reason}"}
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
          {:ok,
           "No OAuth scopes found. You need to reconnect your Google account to grant permissions."}
        else
          scope_descriptions =
            scopes
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
    action_lower = String.downcase(action)
    # Use LLM/tool calling to decide which integration to use
    # If the request is ambiguous, ask the user for clarification
    cond do
      String.contains?(action_lower, "email") or String.contains?(action_lower, "mail") ->
        execute_gmail_action(user, "search", args)
      String.contains?(action_lower, "event") or String.contains?(action_lower, "meeting") ->
        # Only fetch today's events from Google Calendar
        today = Date.utc_today() |> Date.to_iso8601()
        start_of_day = today <> "T00:00:00Z"
        end_of_day = today <> "T23:59:59Z"
        case Calendar.get_events(user, start_of_day, end_of_day) do
          {:ok, events} when is_list(events) and length(events) > 0 ->
            event_list =
              Enum.map(events, fn event ->
                summary = Map.get(event, "summary", "(no title)")
                start_time = get_in(event, ["start", "dateTime"]) || get_in(event, ["start", "date"]) || "(no time)"
                "• #{summary} at #{start_time}"
              end)
              |> Enum.join("\n")
            {:ok, "Your meetings/events today:\n\n" <> event_list}
          {:ok, _} ->
            {:ask_user, "I couldn't find any meetings or events today in your Google Calendar. Would you like me to check your emails or HubSpot for meeting-related information?"}
          {:error, reason} ->
            {:error, "Failed to fetch today's meetings: #{reason}"}
        end
      String.contains?(action_lower, "contact") or String.contains?(action_lower, "person") ->
        execute_contact_action(user, "search", args)
      true ->
        {:ask_user, "Could you clarify your request? For example, do you want to see your calendar events, HubSpot meetings, emails, or something else?"}
    end
  end

  # Format result item for user-friendly output
  defp format_result_item(item, source) do
    case source do
      "Calendar" ->
        summary = Map.get(item, "summary", "(no title)")
        start_time = Map.get(item, "start_time", "(no time)")
        "• #{summary} at #{start_time}"
      "HubSpot Contacts" ->
        name = Map.get(item, "name", "(no name)")
        email = Map.get(item, "email", "(no email)")
        "• #{name} (#{email})"
      "Gmail" ->
        subject = Map.get(item, "subject", "(no subject)")
        from = Map.get(item, "from", "(no sender)")
        "• Email: #{subject} from #{from}"
      _ ->
        inspect(item)
    end
  end

  # Format event for user-friendly output
  defp format_event(event) do
    # Example: "• Meeting with John Doe at 10:00 AM"
    summary = Map.get(event, "summary", "(no title)")
    start_time = Map.get(event, "start_time", "(no time)")
    "• #{summary} at #{start_time}"
  end

  # Format contact for user-friendly output
  defp format_contact(contact) do
    name = Map.get(contact, "name", "(no name)")
    email = Map.get(contact, "email", "(no email)")
    "• #{name} (#{email})"
  end

  # Gmail Tool Executions
  defp execute_gmail_search(user, args) do
    query = Map.get(args, "query", "")
    max_results = Map.get(args, "max_results", 10)

    case Gmail.search_emails(user, query) do
      {:ok, emails} ->
        emails_to_show = Enum.take(emails, max_results)

        email_list =
          Enum.map(emails_to_show, fn email ->
            "• #{email.subject} (from: #{email.from})"
          end)
          |> Enum.join("\n")

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

        email_list =
          Enum.map(emails_to_show, fn email ->
            "• #{email.subject} (from: #{email.from})"
          end)
          |> Enum.join("\n")

        {:ok, "Found #{length(emails)} emails:\n\n#{email_list}"}

      {:error, reason} ->
        {:error, "Failed to list emails: #{reason}"}
    end
  end

  defp execute_gmail_get_message(user, args) do
    message_id = args["message_id"]

    case Gmail.get_email_details(user, message_id) do
      {:ok, email} ->
        {:ok,
         "Email: #{email.subject}\nFrom: #{email.from}\nDate: #{email.date}\n\n#{email.body}"}

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
          event_list =
            Enum.map(events, fn event ->
              start_time =
                get_in(event, ["start", "dateTime"]) || get_in(event, ["start", "date"])

              "• #{event["summary"]} (#{start_time})"
            end)
            |> Enum.join("\n")

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
          event_list =
            Enum.map(events, fn event ->
              start_time =
                get_in(event, ["start", "dateTime"]) || get_in(event, ["start", "date"])

              "• #{event["summary"]} (#{start_time})"
            end)
            |> Enum.join("\n")

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

        {:ok,
         "Event: #{event["summary"]}\nStart: #{start_time}\nEnd: #{end_time}\nDescription: #{event["description"] || "No description"}"}

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
          calendar_list =
            Enum.map(calendars, fn calendar ->
              "• #{calendar["summary"]} (#{calendar["id"]})"
            end)
            |> Enum.join("\n")

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

    case HubSpot.search_contacts(user, query) do
      {:ok, contacts} when is_list(contacts) and length(contacts) > 0 ->
        contact_list =
          Enum.map(contacts, fn contact ->
            properties = contact["properties"] || %{}
            firstname = properties["firstname"] || ""
            lastname = properties["lastname"] || ""
            email = properties["email"] || ""
            company = properties["company"] || ""
            phone = properties["phone"] || ""
            jobtitle = properties["jobtitle"] || ""

            name = "#{firstname} #{lastname}" |> String.trim()
            name = if name == "", do: "Unknown", else: name

            contact_info = "• #{name}"
            contact_info = if email != "", do: contact_info <> " (#{email})", else: contact_info

            contact_info =
              if company != "", do: contact_info <> " - #{company}", else: contact_info

            contact_info =
              if jobtitle != "", do: contact_info <> " (#{jobtitle})", else: contact_info

            contact_info = if phone != "", do: contact_info <> " - #{phone}", else: contact_info

            contact_info
          end)
          |> Enum.join("\n")

        {:ok, "Found #{length(contacts)} HubSpot contacts:\n\n#{contact_list}"}

      {:ok, _} ->
        {:ok, "No HubSpot contacts found."}

      {:error, reason} ->
        {:error, "Failed to search HubSpot contacts: #{reason}"}
    end
  end

  defp execute_contacts_create(_user, _args) do
    # Note: This would need to be implemented in the HubSpot module
    {:ok, "Contact creation not yet implemented"}
  end

  defp execute_check_oauth_scopes(user, _args) do
    case Accounts.get_user_google_account(user.id) do
      nil ->
        {:ok, "No Google account connected. Please connect your Google account first."}

      account ->
        scopes = account.scopes || []

        if Enum.empty?(scopes) do
          {:ok,
           "No OAuth scopes found. You need to reconnect your Google account to grant permissions."}
        else
          scope_descriptions =
            scopes
            |> Enum.map(fn scope ->
              case scope do
                "https://www.googleapis.com/auth/gmail.modify" -> "Gmail (read & send emails)"
                "https://www.googleapis.com/auth/calendar" -> "Calendar (full access)"
                "https://www.googleapis.com/auth/calendar.events" -> "Calendar events"
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

    defp execute_check_ongoing_instructions(user, _args) do
    case AgentInstruction.get_active_instructions_by_user(user.id) do
      {:ok, instructions} when is_list(instructions) and length(instructions) > 0 ->
        instruction_list =
          instructions
          |> Enum.map(fn instruction ->
            trigger_desc = case instruction.trigger_type do
              "email_received" -> "when emails are received"
              "calendar_event_created" -> "when calendar events are created"
              "hubspot_contact_created" -> "when HubSpot contacts are created"
              _ -> "when triggered"
            end

            "• #{instruction.instruction} (#{trigger_desc})"
          end)
          |> Enum.join("\n")

        {:ok, "You have #{length(instructions)} active ongoing instructions:\n\n#{instruction_list}"}

      {:ok, []} ->
        {:ok, "You don't have any active ongoing instructions. You can create them by telling me things like 'When I get an email from someone not in HubSpot, automatically add them to HubSpot' or 'When I create a calendar event, send an email to attendees'."}

      _ ->
        {:error, "Failed to check ongoing instructions"}
    end
  end

  # Generate response from tool execution results
  defp generate_response_from_results(_user_message, results) do
    successful_results =
      Enum.filter(results, fn
        {:ok, _} -> true
        {:error, _} -> false
      end)

    error_results =
      Enum.filter(results, fn
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
    # Allow if any Google account or token is present
    case AdvisorAi.Accounts.get_user_google_account(user.id) do
      nil -> false
      account ->
        (account.access_token != nil and account.access_token != "") or
        (user.google_access_token != nil and user.google_access_token != "")
    end
  end

  defp has_gmail_access?(user) do
    # Allow if any Google account with a token and any gmail-related scope
    case AdvisorAi.Accounts.get_user_google_account(user.id) do
      nil -> false
      account ->
        (account.access_token != nil and account.access_token != "") or
        (user.google_access_token != nil and user.google_access_token != "")
    end
  end

  defp has_calendar_access?(user) do
    case AdvisorAi.Accounts.get_user_google_account(user.id) do
      nil ->
        false

      account ->
        scopes = account.scopes || []

        Enum.any?(scopes, fn scope ->
          String.contains?(scope, "calendar")
        end)
    end
  end

  defp has_hubspot_connection?(user) do
    # Allow if any HubSpot token is present on user or account
    (user.hubspot_access_token != nil and user.hubspot_access_token != "") or
    (user.hubspot_refresh_token != nil and user.hubspot_refresh_token != "") or
    case AdvisorAi.Accounts.get_user_hubspot_account(user.id) do
      nil -> false
      account ->
        (account.access_token != nil and account.access_token != "") or
        (account.refresh_token != nil and account.refresh_token != "")
    end
  end

  def create_agent_response(_user, conversation_id, content, response_type) do
    Chat.create_message(conversation_id, %{
      role: "assistant",
      content: content,
      metadata: %{response_type: response_type}
    })
  end

  def handle_unknown_action(user, conversation_id, action) do
    create_agent_response(
      user,
      conversation_id,
      "Could not determine how to execute action: #{action}",
      "error"
    )
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

  # Determine which tool to use based on parameters
  defp determine_tool_from_params(params, _context) do
    cond do
      # Gmail tools
      Map.has_key?(params, "query") and
          (String.contains?(Map.get(params, "query", ""), "sent") or
             String.contains?(Map.get(params, "query", ""), "from:") or
             String.contains?(Map.get(params, "query", ""), "subject:")) ->
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

  # Recognize if a message is an ongoing instruction
  defp recognize_ongoing_instruction(message) do
    message_lower = String.downcase(message)

    # Check for instruction patterns
    cond do
      # Email-related instructions
      String.contains?(message_lower, "when i get an email") or
          String.contains?(message_lower, "when someone emails me") or
          String.contains?(message_lower, "when an email comes in") or
          String.contains?(message_lower, "when i receive an email") ->
        parse_email_instruction(message)

      # Calendar-related instructions
      String.contains?(message_lower, "when i create") and String.contains?(message_lower, "calendar") or
          String.contains?(message_lower, "when i add") and String.contains?(message_lower, "event") ->
        parse_calendar_instruction(message)

      # HubSpot-related instructions
      String.contains?(message_lower, "when i create") and String.contains?(message_lower, "contact") or
          String.contains?(message_lower, "when someone") and String.contains?(message_lower, "hubspot") ->
        parse_hubspot_instruction(message)

      # Generic automation instructions
      String.contains?(message_lower, "automatically") and
          (String.contains?(message_lower, "send") or String.contains?(message_lower, "create") or
             String.contains?(message_lower, "add") or String.contains?(message_lower, "notify")) ->
        parse_generic_instruction(message)

      # Direct HubSpot + email combinations
      (String.contains?(message_lower, "email") and String.contains?(message_lower, "hubspot")) or
      (String.contains?(message_lower, "email") and String.contains?(message_lower, "contact")) ->
        parse_generic_instruction(message)

      true ->
        {:error, :not_instruction}
    end
  end

  # Parse email-related instructions
  defp parse_email_instruction(message) do
    message_lower = String.downcase(message)

    cond do
      # "When I get an email from someone not already in hubspot, automatically add them to hubspot with a note about the email"
      String.contains?(message_lower, "not already in hubspot") or
          String.contains?(message_lower, "not in hubspot") or
          String.contains?(message_lower, "doesn't exist") or
          String.contains?(message_lower, "doesnt exist") or
          String.contains?(message_lower, "add to hubspot") ->
        {:ok, %{
          trigger_type: "email_received",
          instruction: message,
          conditions: %{
            "check_hubspot" => true,
            "create_contact_if_missing" => true,
            "add_note" => true
          }
        }}

      # "When I get an email from a client, automatically respond with..."
      String.contains?(message_lower, "automatically respond") or
          String.contains?(message_lower, "auto-reply") ->
        {:ok, %{
          trigger_type: "email_received",
          instruction: message,
          conditions: %{
            "auto_reply" => true
          }
        }}

      # Generic email instruction
      true ->
        {:ok, %{
          trigger_type: "email_received",
          instruction: message,
          conditions: %{}
        }}
    end
  end

  # Parse calendar-related instructions
  defp parse_calendar_instruction(message) do
    message_lower = String.downcase(message)

    cond do
      # "When I add an event in my calendar, send an email to attendees"
      String.contains?(message_lower, "send an email to attendees") or
          String.contains?(message_lower, "notify attendees") ->
        {:ok, %{
          trigger_type: "calendar_event_created",
          instruction: message,
          conditions: %{
            "notify_attendees" => true
          }
        }}

      # Generic calendar instruction
      true ->
        {:ok, %{
          trigger_type: "calendar_event_created",
          instruction: message,
          conditions: %{}
        }}
    end
  end

  # Parse HubSpot-related instructions
  defp parse_hubspot_instruction(message) do
    message_lower = String.downcase(message)

    cond do
      # "When I create a contact in HubSpot, send them an email"
      String.contains?(message_lower, "send them an email") or
          String.contains?(message_lower, "send email") ->
        {:ok, %{
          trigger_type: "hubspot_contact_created",
          instruction: message,
          conditions: %{
            "send_welcome_email" => true
          }
        }}

      # Generic HubSpot instruction
      true ->
        {:ok, %{
          trigger_type: "hubspot_contact_created",
          instruction: message,
          conditions: %{}
        }}
    end
  end

  # Parse generic automation instructions
  defp parse_generic_instruction(message) do
    message_lower = String.downcase(message)

    cond do
      # Check for HubSpot + email combinations first
      (String.contains?(message_lower, "email") and String.contains?(message_lower, "hubspot")) or
      (String.contains?(message_lower, "email") and String.contains?(message_lower, "contact")) ->
        {:ok, %{
          trigger_type: "email_received",
          instruction: message,
          conditions: %{
            "check_hubspot" => true,
            "create_contact_if_missing" => true,
            "add_note" => true
          }
        }}

      String.contains?(message_lower, "email") ->
        {:ok, %{
          trigger_type: "email_received",
          instruction: message,
          conditions: %{}
        }}

      String.contains?(message_lower, "calendar") or String.contains?(message_lower, "event") ->
        {:ok, %{
          trigger_type: "calendar_event_created",
          instruction: message,
          conditions: %{}
        }}

      String.contains?(message_lower, "contact") or String.contains?(message_lower, "hubspot") ->
        {:ok, %{
          trigger_type: "hubspot_contact_created",
          instruction: message,
          conditions: %{}
        }}

      true ->
        {:error, :not_instruction}
    end
  end

  # Store the ongoing instruction in the database
  defp store_ongoing_instruction(user, instruction_data) do
    AgentInstruction.create(%{
      user_id: user.id,
      instruction: instruction_data.instruction,
      trigger_type: instruction_data.trigger_type,
      conditions: instruction_data.conditions,
      is_active: true
    })
  end

  # Build confirmation message for stored instruction
  defp build_instruction_confirmation(instruction_data) do
    trigger_description = case instruction_data.trigger_type do
      "email_received" -> "when you receive emails"
      "calendar_event_created" -> "when you create calendar events"
      "hubspot_contact_created" -> "when you create HubSpot contacts"
      _ -> "when triggered"
    end

    "Perfect! I've saved your instruction and will remember to #{instruction_data.instruction} #{trigger_description}. You can manage all your automated instructions in Settings > Instructions."
  end

  defp format_datetime_for_chat(nil), do: "(No time)"
  defp format_datetime_for_chat(dt) do
    case DateTime.from_iso8601(dt) do
      {:ok, dt, _} ->
        # Format as local time string
        Calendar.strftime(dt, "%A, %B %d, %Y at %I:%M %p %Z")
      _ ->
        dt
    end
  end
end
