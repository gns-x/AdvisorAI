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

  # Enhanced process request with memory and RAG for proactive responses
  def process_proactive_request(user, conversation_id, user_message) do
    # Get conversation context
    context = Chat.get_conversation_context(conversation_id)

    # Get relevant context from RAG
    rag_context = get_relevant_context(user.id, user_message)

    # Get active instructions for memory
    active_instructions = get_active_instructions(user.id)

    # Build enhanced context with memory and RAG
    enhanced_context = build_enhanced_context(user, context, rag_context, active_instructions)

    # Process with enhanced context
    process_with_enhanced_context(user, conversation_id, user_message, enhanced_context)
  end

  defp get_relevant_context(user_id, message) do
    # Get embedding for the message
    case get_embedding(message) do
      {:ok, query_embedding} ->
        AdvisorAi.AI.VectorEmbedding.find_similar(user_id, query_embedding, 5)
        |> AdvisorAi.Repo.all()
        |> Enum.map(& &1.content)
        |> Enum.join("\n")

      {:error, _} ->
        ""
    end
  end

  defp get_embedding(text) do
    # Use OpenRouter for RAG
    case OpenRouterClient.embeddings(input: text) do
      {:ok, %{"data" => [%{"embedding" => embedding}]}} ->
        {:ok, embedding}

      {:error, reason} ->
        {:error, "Failed to get embedding: #{reason}"}
    end
  end

  defp get_active_instructions(user_id) do
    case AgentInstruction.get_active_instructions_by_user(user_id) do
      {:ok, instructions} -> instructions
      _ -> []
    end
  end

  defp build_enhanced_context(user, conversation_context, rag_context, active_instructions) do
    # Build instruction memory
    instruction_memory = build_instruction_memory(active_instructions)

    # Build recent conversation memory
    conversation_memory = build_conversation_memory(conversation_context)

    %{
      user: user,
      rag_context: rag_context,
      instruction_memory: instruction_memory,
      conversation_memory: conversation_memory,
      current_time: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp build_instruction_memory(instructions) do
    if Enum.empty?(instructions) do
      "No active ongoing instructions."
    else
      instruction_list =
        instructions
        |> Enum.map(fn instruction ->
          trigger_desc =
            case instruction.trigger_type do
              "email_received" -> "when emails are received"
              "calendar_event_created" -> "when calendar events are created"
              "hubspot_contact_created" -> "when HubSpot contacts are created"
              _ -> "when triggered"
            end

          "• #{instruction.instruction} (#{trigger_desc})"
        end)
        |> Enum.join("\n")

      "Active ongoing instructions:\n#{instruction_list}"
    end
  end

  defp build_conversation_memory(conversation_context) do
    case conversation_context do
      %{recent_memories: memories} when is_list(memories) and length(memories) > 0 ->
        memory_list =
          memories
          |> Enum.map(fn memory ->
            "Request: #{memory["request"]}\nResult: #{memory["result"]}"
          end)
          |> Enum.join("\n\n")

        "Recent interactions:\n#{memory_list}"

      _ ->
        "No recent conversation memory."
    end
  end

  defp process_with_enhanced_context(user, conversation_id, user_message, enhanced_context) do
    # Get available tools
    tools = get_available_tools(user)

    if Enum.empty?(tools) do
      create_agent_response(
        user,
        conversation_id,
        "I need you to connect your accounts first so I can perform real actions. Please go to Settings > Integrations to connect your Gmail, Google Calendar, or HubSpot accounts.",
        "error"
      )
    else
      # Create AI prompt with enhanced context
      prompt = build_enhanced_prompt(user_message, enhanced_context, tools)

      # Get AI response with tool calls
      case get_ai_response_with_tools(prompt, tools) do
        {:ok, ai_response} ->
          execute_ai_tool_calls(user, conversation_id, ai_response, user_message, enhanced_context)

        {:error, reason} ->
          create_agent_response(
            user,
            conversation_id,
            "I'm having trouble understanding your request. Please try rephrasing it.",
            "error"
          )
      end
    end
  end

  defp build_enhanced_prompt(user_message, enhanced_context, tools) do
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
    services_available =
      cond do
        enhanced_context.user.google_connected and enhanced_context.user.gmail_available and
          enhanced_context.user.calendar_available and enhanced_context.user.hubspot_connected ->
          "Gmail, Google Calendar, and HubSpot CRM"

        enhanced_context.user.google_connected and enhanced_context.user.gmail_available and
            enhanced_context.user.hubspot_connected ->
          "Gmail and HubSpot CRM"

        enhanced_context.user.google_connected and enhanced_context.user.calendar_available and
            enhanced_context.user.hubspot_connected ->
          "Google Calendar and HubSpot CRM"

        enhanced_context.user.google_connected and enhanced_context.user.gmail_available ->
          "Gmail and HubSpot CRM"

        enhanced_context.user.google_connected and enhanced_context.user.calendar_available ->
          "Google Calendar and HubSpot CRM"

        enhanced_context.user.hubspot_connected ->
          "HubSpot CRM only"

        enhanced_context.user.google_connected ->
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

    ## APPOINTMENT SCHEDULING INSTRUCTIONS:
    - When asked to schedule an appointment with someone, follow this process:
      1. First, search for the contact by name using universal_action with action="search_contacts"
      2. If contact found, get their email and proceed with scheduling
      3. If contact not found, search previous emails for the person using universal_action with action="search_emails"
      4. Get available times from your calendar using universal_action with action="get_availability" (specify date and duration_minutes)
      5. Send an email proposing available times using universal_action with action="send_email"
      6. When they respond, analyze their response and either schedule the event or propose new times
      7. Add notes in HubSpot about the interaction using universal_action with action="add_note"
    - Always be proactive and intelligent - if someone asks to schedule with "John", search for "John" in contacts first
    - If a contact name is provided but not found, search emails for previous communication with that person
    - When proposing times, include multiple options and ask for their preference
    - After scheduling, always add a note in HubSpot about the appointment
    - Use get_availability with date="YYYY-MM-DD" and duration_minutes=60 (or appropriate duration)

    ## MEMORY AND CONTEXT:
    #{enhanced_context.instruction_memory}

    ## RELEVANT CONTEXT FROM PREVIOUS INTERACTIONS:
    #{enhanced_context.rag_context}

    ## RECENT CONVERSATION MEMORY:
    #{enhanced_context.conversation_memory}

    ## Available Tools:
    #{if Enum.empty?(tools), do: "- No tools available - user needs to connect services first", else: "- universal_action: Execute any Gmail, Calendar, or HubSpot action"}

    ## Tool Usage Examples:
    - To send an email: Use universal_action with action="send_email", to="recipient@email.com", subject="Subject", body="Email body"
    - To create calendar event: Use universal_action with action="create_event", summary="Event title", start_time="2025-07-07T10:00:00Z", end_time="2025-07-07T11:00:00Z"
    - To list today's meetings: Use universal_action with action="list_events", date="2025-07-07"
    - To get all meetings today: Use universal_action with action="get_events", date="2025-07-07"
    - To search contacts: Use universal_action with action="search_contacts", query="search term"
    - To get calendar for today: Use universal_action with action="list_events", date="2025-07-07"
    - To check ongoing instructions: Use universal_action with action="check_ongoing_instructions"

    ## Current User Context:
    - Name: #{enhanced_context.user.name}
    - Email: #{enhanced_context.user.email}
    - Google Connected: #{enhanced_context.user.google_connected}
    - Gmail Available: #{enhanced_context.user.gmail_available}
    - Calendar Available: #{enhanced_context.user.calendar_available}
    - HubSpot Connected: #{enhanced_context.user.hubspot_connected}
    - Current Time: #{enhanced_context.current_time}

    ## User Request: "#{user_message}"

    IMPORTANT: You MUST use the universal_action tool to perform the requested action. Do NOT generate fake responses or pretend to perform actions. Use the tool with the appropriate action and parameters.

    For the user's request "#{user_message}", you MUST:
    1. Consider the ongoing instructions and previous context
    2. Determine what action is needed (send_email, create_event, list_events, get_events, search_contacts, etc.)
    3. For meetings/events/calendar requests, ALWAYS use Google Calendar first.
    4. Use the universal_action tool with the correct action and parameters
    5. Return only the tool call result, not a fake response
    """
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

        recent_memories =
          (context["recent_memories"] || []) ++
            [%{"request" => user_message, "result" => summary}]

        Chat.update_conversation_context(
          conversation_id,
          Map.merge(context, %{
            "workflow_state" => new_state,
            "recent_memories" => Enum.take(recent_memories, -10)
          })
        )

        # Ask user for update/clarification if needed
        case AI.WorkflowGenerator.next_action_llm(new_state, recent_memories) do
          {:ask_user, question} ->
            create_agent_response(user, conversation_id, question, "conversation")

          {:next_step, _llm_step} ->
            resume_workflow(user, conversation_id, user_message, new_state)

          {:edge_case, edge_case_info} ->
            handle_edge_case(user, conversation_id, edge_case_info, new_state)

          {:done, result} ->
            Chat.update_conversation_context(
              conversation_id,
              Map.delete(context, "workflow_state")
            )

            create_agent_response(
              user,
              conversation_id,
              summarize_final_result(result, recent_memories),
              "action"
            )
        end

      {:done, result} ->
        context = Chat.get_conversation_context(conversation_id)

        recent_memories =
          (context["recent_memories"] || []) ++ [%{"request" => user_message, "result" => result}]

        Chat.update_conversation_context(
          conversation_id,
          Map.merge(context, %{
            "recent_memories" => Enum.take(recent_memories, -10),
            "workflow_state" => nil
          })
        )

        create_agent_response(
          user,
          conversation_id,
          summarize_final_result(result, recent_memories),
          "action"
        )

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
    case result do
      {:ask_user, prompt} ->
        prompt
      {:ok, message} when is_binary(message) ->
        message
      message when is_binary(message) ->
        message
      _ ->
        # Fallback: summarize recent steps in a friendly way
        steps = Enum.map_join(recent_memories, ", ", fn m -> m["request"] end)
        "I've completed your request. If you need more details or want to clarify, just ask! (Recent steps: #{steps})"
    end
  end

  # Handle edge cases using LLM/tool calling
  defp handle_edge_case(user, conversation_id, edge_case_info, workflow_state) do
    # Use LLM/tool calling to resolve edge case, then continue workflow
    case AI.WorkflowGenerator.resolve_edge_case(edge_case_info, workflow_state) do
      {:ok, new_state} ->
        resume_workflow(user, conversation_id, workflow_state["last_user_message"], new_state)

      {:done, result} ->
        Chat.update_conversation_context(
          conversation_id,
          Map.delete(Chat.get_conversation_context(conversation_id), "workflow_state")
        )

        create_agent_response(user, conversation_id, result, "action")

      _ ->
        Chat.update_conversation_context(
          conversation_id,
          Map.delete(Chat.get_conversation_context(conversation_id), "workflow_state")
        )

        create_agent_response(user, conversation_id, "Edge case error.", "error")
    end
  end

  # Start a new workflow or process as normal
  defp process_or_start_workflow(user, conversation_id, user_message) do
    # Detect 'Schedule an appointment with [Name]' and create persistent instruction
    case Regex.run(~r/^schedule an appointment with ([a-zA-Z .'-]+)$/i, String.trim(user_message)) do
      [_, name] ->
        # Build a persistent instruction for this contact
        instruction_text = "When I receive an email from #{name}, automatically handle appointment scheduling: look up in HubSpot, email with available times, add to calendar, update HubSpot, and follow up as needed."
        instruction_data = %{
          trigger_type: "email_received",
          instruction: instruction_text,
          conditions: %{
            "appointment_workflow" => true,
            "contact_name" => name
          }
        }
        store_ongoing_instruction(user, instruction_data)
        # Show confirmation message in chat
        confirmation = build_instruction_confirmation(instruction_data)
        create_agent_response(user, conversation_id, confirmation, "conversation")
        # Proceed with the normal workflow for this request as well
        process_normal_request(user, conversation_id, user_message)
      _ ->
        # Use WorkflowGenerator to check if this is a complex request
        case AI.WorkflowGenerator.generate_workflow(user_message) do
          {:ok, workflow} ->
            if is_map(workflow) and Map.has_key?(workflow, "steps") and is_list(workflow["steps"]) do
              # Start new workflow state
              workflow_state = %{
                "active" => true,
                "workflow" => workflow,
                "current_step" => 0,
                "results" => [],
                "last_user_message" => user_message
              }

              Chat.update_conversation_context(
                conversation_id,
                Map.put(
                  Chat.get_conversation_context(conversation_id),
                  "workflow_state",
                  workflow_state
                )
              )

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

            "new_available_times" ->
              {k, extract_new_available_times_from_results(extracted_data)}

            _ ->
              {k, v}
          end
        end)

      # Handle special workflow actions
      case action do
        "wait_for_reply" ->
          # This is a pause point - wait for user/contact response
          {:done, "Waiting for reply from contact. Please respond to continue the workflow."}

        "conditional_schedule" ->
          # Check condition and schedule if met
          condition = Map.get(params, "condition")
          if evaluate_condition(condition, workflow_state) do
            tool_call = %{"name" => "universal_action", "arguments" => Map.put(params, "action", "create_event")}
            result = execute_tool_call(user, tool_call, workflow_state["last_user_message"] || "")
            update_workflow_state(workflow_state, result)
          else
            update_workflow_state(workflow_state, {:ok, "Condition not met, skipping scheduling"})
          end

        "conditional_send_new_times" ->
          # Check condition and send new times if needed
          condition = Map.get(params, "condition")
          if evaluate_condition(condition, workflow_state) do
            tool_call = %{"name" => "universal_action", "arguments" => Map.put(params, "action", "send_email")}
            result = execute_tool_call(user, tool_call)
            update_workflow_state(workflow_state, result)
          else
            update_workflow_state(workflow_state, {:ok, "Condition not met, skipping new times"})
          end

        "conditional_send_confirmation" ->
          # Check condition and send confirmation if appointment was scheduled
          condition = Map.get(params, "condition")
          if evaluate_condition(condition, workflow_state) do
            tool_call = %{"name" => "universal_action", "arguments" => Map.put(params, "action", "send_email")}
            result = execute_tool_call(user, tool_call)
            update_workflow_state(workflow_state, result)
          else
            update_workflow_state(workflow_state, {:ok, "Condition not met, skipping confirmation"})
          end

        "analyze_email_response" ->
          # Use LLM to analyze email response
          result = analyze_email_response_with_llm(user, conversation_id, workflow_state)
          update_workflow_state(workflow_state, result)

        _ ->
          # Standard tool call execution
          tool_call = %{"name" => api, "arguments" => Map.put(params, "action", action)}
          result = execute_tool_call(user, tool_call)
          update_workflow_state(workflow_state, result)
      end
    end
  end

  defp update_workflow_state(workflow_state, result) do
    new_results = (workflow_state["results"] || []) ++ [result]

    new_state =
      workflow_state
      |> Map.put("current_step", (workflow_state["current_step"] || 0) + 1)
      |> Map.put("results", new_results)

    if new_state["current_step"] < length(workflow_state["workflow"]["steps"]) do
      {:continue, new_state}
    else
      {:done, "Workflow complete. Results: #{inspect(new_results)}"}
    end
  end

  defp evaluate_condition(condition, workflow_state) do
    case condition do
      "if_chosen_time_exists" ->
        extract_chosen_time_from_results(workflow_state["results"] || []) != ""

      "if_needs_new_times" ->
        needs_new_times = extract_needs_new_times_from_results(workflow_state["results"] || [])
        needs_new_times == true

      "if_appointment_scheduled" ->
        # Check if any result indicates successful scheduling
        results = workflow_state["results"] || []
        Enum.any?(results, fn
          {:ok, result} when is_binary(result) -> String.contains?(result, "scheduled") or String.contains?(result, "Appointment")
          _ -> false
        end)

      _ ->
        true  # Default to executing
    end
  end

  defp analyze_email_response_with_llm(user, conversation_id, workflow_state) do
    # Get the last email response from the contact
    contact_email = extract_contact_email_from_results(workflow_state["results"] || [])

    if contact_email != "" do
      # Search for recent emails from this contact
      case Gmail.search_emails(user, "from:#{contact_email}") do
        {:ok, emails} when length(emails) > 0 ->
          latest_email = List.first(emails)

          # Use LLM to analyze the response
          analysis_prompt = """
          Analyze this email response for appointment scheduling:

          From: #{latest_email.from}
          Subject: #{latest_email.subject}
          Body: #{latest_email.body}

          Determine:
          1. Did they accept any of the proposed times?
          2. Did they reject all times and need alternatives?
          3. Did they suggest a different time?
          4. What is their preferred time (if any)?

          Respond with JSON:
          {
            "response_type": "accepted|rejected|suggested|unclear",
            "chosen_time": "extracted time or empty string",
            "needs_new_times": true/false,
            "suggested_time": "their suggested time or empty string"
          }
          """

          case OpenRouterClient.chat_completion(
                 messages: [
                   %{role: "system", content: "You are an expert at analyzing email responses for appointment scheduling."},
                   %{role: "user", content: analysis_prompt}
                 ]
               ) do
            {:ok, %{"choices" => [%{"message" => %{"content" => response}}]}} ->
              case Jason.decode(response) do
                {:ok, analysis} ->
                  {:ok, analysis}
                {:error, _} ->
                  {:ok, %{"response_type" => "unclear", "chosen_time" => "", "needs_new_times" => false}}
              end

            {:error, _} ->
              {:ok, %{"response_type" => "unclear", "chosen_time" => "", "needs_new_times" => false}}
          end

        _ ->
          {:ok, %{"response_type" => "no_response", "chosen_time" => "", "needs_new_times" => false}}
      end
    else
      {:ok, %{"response_type" => "no_contact", "chosen_time" => "", "needs_new_times" => false}}
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

  defp extract_new_available_times_from_results(results) do
    # Find new available times from calendar step
    results
    |> Enum.find_value(fn
      {:ok, times} when is_list(times) -> Enum.join(times, ", ")
      {:ok, %{"new_available_times" => times}} -> times
      _ -> nil
    end) || ""
  end

  defp extract_needs_new_times_from_results(results) do
    # Find needs_new_times from LLM analysis results
    results
    |> Enum.find_value(fn
      {:ok, %{"needs_new_times" => needs}} -> needs
      _ -> nil
    end) || false
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
              },
              check_ongoing_instructions: %{
                type: "boolean",
                description: "Set to true to check for active ongoing instructions for the user."
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
    services_available =
      cond do
        context.user.google_connected and context.user.gmail_available and
          context.user.calendar_available and context.user.hubspot_connected ->
          "Gmail, Google Calendar, and HubSpot CRM"

        context.user.google_connected and context.user.gmail_available and
            context.user.hubspot_connected ->
          "Gmail and HubSpot CRM"

        context.user.google_connected and context.user.calendar_available and
            context.user.hubspot_connected ->
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

    # Get recent context for better decision making
    recent_context = get_recent_context_for_llm(context)

    """
    You are an EXTREMELY intelligent and proactive AI assistant for financial advisors. You have access to: #{services_available}

    ## CRITICAL INSTRUCTIONS FOR PROACTIVE INTELLIGENCE:
    1. **BE EXTREMELY PROACTIVE**: Don't just execute what's asked - anticipate needs and provide maximum value
    2. **USE LLM REASONING**: For every request, think through edge cases, alternatives, and intelligent solutions
    3. **HANDLE AMBIGUITY**: If a request is unclear, make intelligent assumptions based on context and patterns
    4. **BE FLEXIBLE**: If the exact action isn't available, find the closest alternative or suggest improvements
    5. **CONSIDER RELATIONSHIPS**: Think about contact relationships, follow-ups, and long-term value
    6. **ANTICIPATE PROBLEMS**: Look for potential issues and suggest solutions before they become problems
    7. **PROVIDE CONTEXT**: Always consider recent conversations and user patterns when making decisions
    8. **NEVER generate fake data** - ALWAYS use the available tools to perform real actions

    ## PROACTIVE BEHAVIOR PATTERNS:

    **Calendar Intelligence:**
    - When checking meetings, also look for conflicts, preparation needs, or follow-up opportunities
    - When creating events, suggest sending invites, adding notes, or scheduling follow-ups
    - When finding availability, consider travel time, buffer periods, and user preferences
    - Always check for overlapping events and suggest rescheduling if needed

    **Email Intelligence:**
    - When sending emails, suggest follow-up actions, calendar events, or HubSpot notes
    - When searching emails, look for patterns, priorities, and relationship context
    - When receiving emails, suggest adding contacts to HubSpot or scheduling responses
    - Consider email threading and conversation history for better responses

    **HubSpot Intelligence:**
    - When searching contacts, offer to create new ones or suggest relationship building actions
    - When creating contacts, suggest welcome emails, follow-up schedules, or notes
    - When adding notes, consider the context and suggest related actions
    - Always think about relationship development and client lifecycle

    **Cross-Platform Intelligence:**
    - Connect email conversations to calendar events and HubSpot contacts
    - Suggest follow-up actions across all platforms
    - Look for patterns in user behavior and suggest optimizations
    - Consider the full client journey across all touchpoints

    ## EDGE CASE HANDLING:
    - If an action fails, try alternative approaches or suggest workarounds
    - If data is missing, make intelligent assumptions or ask for clarification
    - If permissions are insufficient, suggest what's needed and why
    - If something is ambiguous, choose the most likely interpretation and explain your reasoning
    - Always provide helpful error messages with actionable suggestions

    ## Available Tools:
    #{if Enum.empty?(tools), do: "- No tools available - user needs to connect services first", else: "- universal_action: Execute any Gmail, Calendar, or HubSpot action"}

    ## Tool Usage Examples:
    - To send an email: Use universal_action with action="send_email", to="recipient@email.com", subject="Subject", body="Email body"
    - To create calendar event: Use universal_action with action="create_event", summary="Event title", start_time="2025-07-07T10:00:00Z", end_time="2025-07-07T11:00:00Z"
    - To list today's meetings: Use universal_action with action="list_events", date="2025-07-07"
    - To get all meetings today: Use universal_action with action="get_events", date="2025-07-07"
    - To search contacts: Use universal_action with action="search_contacts", query="search term"
    - To get calendar for today: Use universal_action with action="list_events", date="2025-07-07"
    - To check ongoing instructions: Use universal_action with action="check_ongoing_instructions"

    ## Current User Context:
    - Name: #{context.user.name}
    - Email: #{context.user.email}
    - Google Connected: #{context.user.google_connected}
    - Gmail Available: #{context.user.gmail_available}
    - Calendar Available: #{context.user.calendar_available}
    - HubSpot Connected: #{context.user.hubspot_connected}
    - Current Time: #{context.current_time}
    - Recent Context: #{recent_context}

    ## User Request: \"#{user_message}\"

    INTELLIGENT ANALYSIS PROCESS:
    1. **What does the user REALLY want to accomplish?** (Look beyond the surface request)
    2. **What would be the most helpful and proactive response?** (Consider additional value)
    3. **Are there any edge cases or potential issues?** (Anticipate problems)
    4. **What additional actions would be valuable?** (Think about follow-ups and relationships)
    5. **How can I use the available tools most effectively?** (Optimize for success)
    6. **What context from recent conversations is relevant?** (Use historical patterns)

    IMPORTANT: You MUST use the universal_action tool to perform the requested action. Do NOT generate fake responses or pretend to perform actions. Use the tool with the appropriate action and parameters, and be intelligent about providing maximum value.
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
          "You are an EXTREMELY intelligent and proactive AI assistant for financial advisors with access to Gmail, Google Calendar, and HubSpot CRM.

CRITICAL INSTRUCTIONS:
1. **ALWAYS use the provided tools** - NEVER generate fake responses or pretend to perform actions
2. **BE EXTREMELY PROACTIVE** - Don't just execute what's asked, anticipate needs and provide maximum value
3. **USE LLM REASONING** - For every request, think through edge cases, alternatives, and intelligent solutions
4. **HANDLE AMBIGUITY** - If a request is unclear, make intelligent assumptions based on context and patterns
5. **BE FLEXIBLE** - If the exact action isn't available, find the closest alternative or suggest improvements
6. **CONSIDER RELATIONSHIPS** - Think about contact relationships, follow-ups, and long-term value
7. **ANTICIPATE PROBLEMS** - Look for potential issues and suggest solutions before they become problems

PROACTIVE BEHAVIOR PATTERNS:
- When checking meetings, also look for conflicts, preparation needs, or follow-up opportunities
- When sending emails, suggest follow-up actions, calendar events, or HubSpot notes
- When searching contacts, offer to create new ones or suggest relationship building actions
- When creating events, suggest sending invites, adding notes, or scheduling follow-ups
- Connect email conversations to calendar events and HubSpot contacts
- Look for patterns in user behavior and suggest optimizations

EDGE CASE HANDLING:
- If an action fails, try alternative approaches or suggest workarounds
- If data is missing, make intelligent assumptions or ask for clarification
- If something is ambiguous, choose the most likely interpretation and explain your reasoning
- Always provide helpful error messages with actionable suggestions

IMPORTANT: When the user asks you to perform an action, you MUST use the universal_action tool with the appropriate action and parameters. Do NOT write fake responses like 'Email sent successfully' - actually call the tools."
      },
      %{"role" => "user", "content" => prompt}
    ]

    IO.inspect(messages, label: "DEBUG: OpenRouter messages")
    IO.inspect(tools_format, label: "DEBUG: OpenRouter tools_format")

    case OpenRouterClient.chat_completion(
           messages: messages,
           tools: tools_format,
           tool_choice: "auto",
           temperature: 0.1
         ) do
      {:ok, response} ->
        IO.inspect(response, label: "DEBUG: OpenRouter raw response")
        {:ok, response}

      {:error, err} ->
        IO.inspect(err, label: "DEBUG: OpenRouter error")
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

  # Execute AI tool calls with intelligent error handling and retry logic
  defp execute_ai_tool_calls(user, conversation_id, ai_response, user_message, context) do
    IO.puts("DEBUG: Parsing tool calls from AI response...")

    case parse_tool_calls(ai_response) do
      {:ok, tool_calls} when tool_calls != [] ->
        IO.puts("DEBUG: Tool calls found: #{inspect(tool_calls)}")
        # Execute each tool call with intelligent retry and error handling
        results =
          Enum.map(tool_calls, fn tool_call ->
            IO.puts("DEBUG: Executing tool call: #{inspect(tool_call)}")
            execute_tool_call_with_retry(user, tool_call, user_message, context)
          end)

        # Process results intelligently
        response_text = process_tool_call_results(results, user_message, context)
        create_agent_response(user, conversation_id, response_text, "action")

      {:ok, []} ->
        # No tool calls found, check if this is a fake response
        response_text = extract_text_response(ai_response)
        IO.puts("DEBUG: No tool calls found. Response text: #{inspect(response_text)}")
        # Always try to extract and execute tool calls from the text, even if not marked as fake
        case extract_bash_style_tool_calls(response_text) do
          {:ok, tool_calls} when tool_calls != [] ->
            IO.puts(
              "DEBUG: Extracted bash-style tool calls (even if not fake): #{inspect(tool_calls)}"
            )

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
            if Regex.match?(~r/universal_action\s*\(/, response_text) or
                 Regex.match?(~r/universal_action\s+action=/, response_text) do
              IO.puts(
                "DEBUG: Tool call pattern found in text but not parsed. Forcing extraction and execution."
              )

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

                  create_agent_response(
                    user,
                    conversation_id,
                    "Sorry, I could not execute your request. Please try again.",
                    "error"
                  )
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
                      response_text ||
                        "I'm not sure how to help with that yet, but I'm learning!",
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
            IO.puts(
              "DEBUG: Extracted bash-style tool calls (even if not fake): #{inspect(tool_calls)}"
            )

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
          "content" =>
            "You are an AI assistant that MUST use tools to perform actions. NEVER generate fake responses. Always use the provided tools."
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
    tool_call_pattern1 =
      ~r/universal_action\s+action="([^"]+)"([^`]*?)(?=\n|$|universal_action|```)/

    # Pattern 2: universal_action(action="...", ...)
    tool_call_pattern2 = ~r/universal_action\(([^)]*)\)/

    # Pattern 3: universal_action --action=... --param=value ...
    tool_call_pattern3 = ~r/universal_action\s+((?:--\w+=\"[^\"]*\"|--\w+=\S+)+)/

    tool_calls = []

    # Match pattern 1
    matches1 = Regex.scan(tool_call_pattern1, content)

    tool_calls1 =
      Enum.map(matches1, fn [_, action, params_string] ->
        args = %{"action" => action}
        param_pattern = ~r/(\w+)="([^"]*)"/
        params = Regex.scan(param_pattern, params_string)
        args = Enum.reduce(params, args, fn [_, key, value], acc -> Map.put(acc, key, value) end)
        %{"name" => "universal_action", "arguments" => args}
      end)

    # Match pattern 2
    matches2 = Regex.scan(tool_call_pattern2, content)

    tool_calls2 =
      Enum.map(matches2, fn [_, params_string] ->
        # params_string is like: action="search_contacts", query="Hamza Hadioui"
        param_pattern = ~r/(\w+)="([^"]*)"/
        params = Regex.scan(param_pattern, params_string)
        args = Enum.reduce(params, %{}, fn [_, key, value], acc -> Map.put(acc, key, value) end)
        %{"name" => "universal_action", "arguments" => args}
      end)

    # Match pattern 3
    matches3 = Regex.scan(tool_call_pattern3, content)

    tool_calls3 =
      Enum.map(matches3, fn [_, params_string] ->
        # params_string is like: --action=list_events --date="2025-07-07"
        param_pattern = ~r/--(\w+)=((?:"[^"]*")|(?:\S+))/
        params = Regex.scan(param_pattern, params_string)

        args =
          Enum.reduce(params, %{}, fn [_, key, value], acc ->
            # Remove quotes if present, but only if value is a binary
            clean_value =
              if is_binary(value) and String.starts_with?(value, "\"") and
                   String.ends_with?(value, "\"") do
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
  defp execute_tool_call(user, tool_call, user_message \\ "") do
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
      "universal_action" -> execute_universal_action(user, arguments, user_message)
      _ -> execute_universal_action(user, function_name, arguments, user_message)
    end
  end

  # Universal Action Execution - Handles ANY request dynamically
  defp execute_universal_action(user, args, user_message \\ "") do
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

      String.contains?(action_lower, "get") and
          (String.contains?(action_lower, "availability") or String.contains?(action_lower, "available")) ->
        execute_calendar_action(user, "get_availability", args)

      String.contains?(action_lower, "find") and
          (String.contains?(action_lower, "meeting") or String.contains?(action_lower, "event")) ->
        execute_calendar_action(user, "find_meetings", args)

      String.contains?(action_lower, "search") and
          (String.contains?(action_lower, "meeting") or String.contains?(action_lower, "event")) ->
        execute_calendar_action(user, "search_meetings", args)

      # Contact actions
      String.contains?(action_lower, "search") and String.contains?(action_lower, "contact") ->
        execute_contact_action(user, "search", args, user_message)

      String.contains?(action_lower, "create") and String.contains?(action_lower, "contact") ->
        execute_contact_action(user, "create", args, user_message)

      String.contains?(action_lower, "add") and String.contains?(action_lower, "note") ->
        execute_contact_action(user, "add_note", args, user_message)

      # OAuth actions
      String.contains?(action_lower, "check") and
          (String.contains?(action_lower, "permission") or String.contains?(action_lower, "scope") or
             String.contains?(action_lower, "oauth")) ->
        execute_oauth_action(user, args)

      # Instruction management actions
      (String.contains?(action_lower, "check_ongoing_instructions")) or
        (action_lower == "check_ongoing_instructions") or
        (Map.get(args, "check_ongoing_instructions", false) == true) ->
        execute_check_ongoing_instructions(user, args)

      # Default - try to infer from action name
      true ->
        execute_inferred_action(user, action, args)
    end
  end

  # Legacy support for old function names
  defp execute_universal_action(user, action, args, user_message) do
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
        execute_contact_action(user, "search", args, user_message)

      String.contains?(action_lower, "contact") and String.contains?(action_lower, "create") ->
        execute_contact_action(user, "create", args, user_message)

      String.contains?(action_lower, "add") and String.contains?(action_lower, "note") ->
        execute_contact_action(user, "add_note", args, user_message)

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

            start_time =
              get_in(created_event, ["start", "dateTime"]) ||
                get_in(created_event, ["start", "date"]) || "(No start time)"

            end_time =
              get_in(created_event, ["end", "dateTime"]) || get_in(created_event, ["end", "date"]) ||
                "(No end time)"

            attendees =
              (created_event["attendees"] || [])
              |> Enum.map(fn a -> a["email"] end)
              |> Enum.join(", ")

            # Format times for readability (show local time if possible)
            formatted_start = format_datetime_for_chat(start_time)
            formatted_end = format_datetime_for_chat(end_time)

            response =
              "✅ Appointment scheduled!\n" <>
                "Title: #{summary}\n" <>
                "Start: #{formatted_start}\n" <>
                "End:   #{formatted_end}" <>
                if attendees != "", do: "\nAttendees: #{attendees}", else: ""

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

      "get_availability" ->
        date = Map.get(args, "date") || Map.get(args, :date) || Date.utc_today() |> Date.to_string()
        duration_minutes = Map.get(args, "duration_minutes") || Map.get(args, :duration_minutes) || 30

        case Calendar.get_availability(user, date, duration_minutes) do
          {:ok, availability} ->
            # Format availability for display
            formatted_times = format_availability_times(availability)
            {:ok, formatted_times}
          {:error, reason} ->
            {:error, "Failed to get calendar availability: #{reason}"}
        end

      "find_meetings" ->
        # Find meetings by attendee email or other criteria
        attendee_email = Map.get(args, "attendee_email") || Map.get(args, :attendee_email)
        query = Map.get(args, "query") || Map.get(args, :query)

        if attendee_email do
          # Search for meetings with this attendee
          case Calendar.list_events(user, time_min: DateTime.utc_now() |> DateTime.to_iso8601()) do
            {:ok, events} when is_list(events) and length(events) > 0 ->
              # Filter events that have this attendee
              matching_events =
                events
                |> Enum.filter(fn event ->
                  attendees = event["attendees"] || []
                  Enum.any?(attendees, fn attendee ->
                    attendee["email"] == attendee_email
                  end)
                end)
                |> Enum.take(5)  # Limit to 5 most recent

              if length(matching_events) > 0 do
                event_list =
                  Enum.map(matching_events, fn event ->
                    start_time = get_in(event, ["start", "dateTime"]) || get_in(event, ["start", "date"])
                    end_time = get_in(event, ["end", "dateTime"]) || get_in(event, ["end", "date"])
                    summary = event["summary"] || "Untitled Event"

                    "• #{summary} (#{format_datetime_for_chat(start_time)} - #{format_datetime_for_chat(end_time)})"
                  end)
                  |> Enum.join("\n")

                {:ok, "Found #{length(matching_events)} upcoming meetings with #{attendee_email}:\n\n#{event_list}"}
              else
                {:ok, "No upcoming meetings found with #{attendee_email}"}
              end

            {:ok, _} ->
              {:ok, "No upcoming meetings found with #{attendee_email}"}

            {:error, reason} ->
              {:error, "Failed to search meetings: #{reason}"}
          end
        else
          # General meeting search
          case Calendar.list_events(user, time_min: DateTime.utc_now() |> DateTime.to_iso8601()) do
            {:ok, events} when is_list(events) and length(events) > 0 ->
              event_list =
                events
                |> Enum.take(5)
                |> Enum.map(fn event ->
                  start_time = get_in(event, ["start", "dateTime"]) || get_in(event, ["start", "date"])
                  summary = event["summary"] || "Untitled Event"

                  "• #{summary} (#{format_datetime_for_chat(start_time)})"
                end)
                |> Enum.join("\n")

              {:ok, "Found #{length(events)} upcoming meetings:\n\n#{event_list}"}

            {:ok, _} ->
              {:ok, "No upcoming meetings found"}

            {:error, reason} ->
              {:error, "Failed to search meetings: #{reason}"}
          end
        end

      "search_meetings" ->
        # Search meetings by query (title, description, etc.)
        query = Map.get(args, "query") || Map.get(args, :query) || ""

        case Calendar.list_events(user, time_min: DateTime.utc_now() |> DateTime.to_iso8601()) do
          {:ok, events} when is_list(events) and length(events) > 0 ->
            # Filter events that match the query
            matching_events =
              events
              |> Enum.filter(fn event ->
                summary = String.downcase(event["summary"] || "")
                description = String.downcase(event["description"] || "")
                query_lower = String.downcase(query)

                String.contains?(summary, query_lower) or String.contains?(description, query_lower)
              end)
              |> Enum.take(5)

            if length(matching_events) > 0 do
              event_list =
                Enum.map(matching_events, fn event ->
                  start_time = get_in(event, ["start", "dateTime"]) || get_in(event, ["start", "date"])
                  summary = event["summary"] || "Untitled Event"

                  "• #{summary} (#{format_datetime_for_chat(start_time)})"
                end)
                |> Enum.join("\n")

              {:ok, "Found #{length(matching_events)} meetings matching '#{query}':\n\n#{event_list}"}
            else
              {:ok, "No meetings found matching '#{query}'"}
            end

          {:ok, _} ->
            {:ok, "No meetings found matching '#{query}'"}

          {:error, reason} ->
            {:error, "Failed to search meetings: #{reason}"}
        end

      _ ->
        {:error, "Unknown calendar action: #{action}"}
    end
  end

  defp execute_contact_action(user, operation, args, user_message \\ "") do
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
              {:ok,
               "No contacts were found in your HubSpot account. You can add new contacts in HubSpot or try a different search."}

            {:error, reason} ->
              {:error, "Failed to list HubSpot contacts: #{reason}"}
          end
        else
          # Query provided, use search_contacts
          case HubSpot.search_contacts(user, query) do
            {:ok, contacts} when is_list(contacts) and length(contacts) > 0 ->
              # Check if this is an appointment scheduling request
              is_appointment_request =
                String.contains?(String.downcase(user_message), "schedule") or
                String.contains?(String.downcase(user_message), "appointment") or
                String.contains?(String.downcase(user_message), "meeting")

              if is_appointment_request and length(contacts) == 1 do
                # This is an appointment request with exactly one contact found
                contact = List.first(contacts)
                properties = contact["properties"] || %{}
                firstname = properties["firstname"] || ""
                lastname = properties["lastname"] || ""
                email = properties["email"] || ""
                name = "#{firstname} #{lastname}" |> String.trim()

                if email != "" do
                  # Found contact with email - proceed with appointment scheduling
                  # Get available times for today and tomorrow
                  today = Date.utc_today() |> Date.to_iso8601()
                  tomorrow = Date.add(Date.utc_today(), 1) |> Date.to_iso8601()

                  case Calendar.get_availability(user, today, 60) do
                    {:ok, today_times} ->
                      case Calendar.get_availability(user, tomorrow, 60) do
                        {:ok, tomorrow_times} ->
                          # Format available times
                          available_times =
                            (today_times ++ tomorrow_times)
                            |> Enum.take(6)  # Limit to 6 options
                            |> Enum.map(fn slot ->
                              start_time = slot["start"]
                              case DateTime.from_iso8601(start_time) do
                                {:ok, dt, _} ->
                                  formatted = Calendar.strftime(dt, "%A, %B %d at %I:%M %p")
                                  "• #{formatted}"
                                _ -> nil
                              end
                            end)
                            |> Enum.filter(&(&1 != nil))
                            |> Enum.join("\n")

                          # Send appointment proposal email
                          email_body = """
                          Hi #{firstname},

                          I hope this email finds you well. I'd like to schedule an appointment with you.

                          Here are some available times I have:

                          #{available_times}

                          Please let me know which time works best for you, or if you'd prefer a different day/time.

                          Best regards,
                          #{user.name}
                          """

                          case Gmail.send_email(user, email, "Appointment Scheduling", email_body) do
                            {:ok, _} ->
                              # Add note to HubSpot
                              note_content = "Sent appointment scheduling email with available times. Waiting for response."
                              HubSpot.add_note(user, email, note_content)

                              {:ok, "Perfect! I found #{name} in your HubSpot contacts (#{email}). I've sent them an email with available appointment times and added a note to their contact record. I'll let you know when they respond so we can schedule the appointment."}

                            {:error, reason} ->
                              {:ok, "I found #{name} in your contacts (#{email}), but I couldn't send the email: #{reason}. You can send the appointment request manually."}
                          end

                        {:error, _} ->
                          {:ok, "I found #{name} in your contacts (#{email}), but I couldn't get your calendar availability. You can send them an email manually to schedule the appointment."}
                      end

                    {:error, _} ->
                      {:ok, "I found #{name} in your contacts (#{email}), but I couldn't get your calendar availability. You can send them an email manually to schedule the appointment."}
                  end
                else
                  # Contact found but no email
                  contact_list = format_contact_list(contacts)
                  {:ok, "Found #{name} in your contacts, but they don't have an email address. Here are the contact details:\n\n#{contact_list}\n\nYou'll need to add their email address to schedule an appointment."}
                end
              else
                # Regular contact search (not appointment scheduling)
                contact_list = format_contact_list(contacts)
                {:ok, "Found #{length(contacts)} HubSpot contacts:\n\n#{contact_list}"}
              end

                        {:ok, _} ->
              # Try to extract email from query for proactive contact creation
              email = extract_email_from_query(query)
              name = extract_name_from_query(query)

              if email do
                # Automatically create the contact if email is found
                {first_name, last_name} = parse_name(name)
                contact_data = %{
                  "email" => email,
                  "first_name" => first_name,
                  "last_name" => last_name,
                  "company" => ""
                }

                case HubSpot.create_contact(user, contact_data) do
                  {:ok, _message} ->
                    {:ok, "I've automatically created a new HubSpot contact for #{name} (#{email}). The contact has been added to your HubSpot account."}
                  {:error, reason} ->
                    {:ok, "I found an email address (#{email}) but couldn't create the contact automatically: #{reason}. You can try creating it manually in HubSpot."}
                end
              else
                # Try to search emails for this person
                case Gmail.search_emails(user, query) do
                  {:ok, emails} when is_list(emails) and length(emails) > 0 ->
                    emails = Enum.take(emails, 5)
                    # Found emails - extract email addresses and offer to create contact
                    email_addresses =
                      emails
                      |> Enum.map(fn email ->
                        Map.get(email, "from", "") |> extract_email_from_string()
                      end)
                      |> Enum.filter(&(&1 != nil))
                      |> Enum.uniq()

                    if length(email_addresses) > 0 do
                      email_list = Enum.join(email_addresses, ", ")
                      {:ok, "I didn't find '#{query}' in your HubSpot contacts, but I found #{length(emails)} emails from this person. I can see email addresses: #{email_list}. Would you like me to create a HubSpot contact for them? Just let me know which email address to use."}
                    else
                      {:ok, "I didn't find '#{query}' in your HubSpot contacts, but I found #{length(emails)} emails from this person. However, I couldn't extract a clear email address. If you have their email address, I can create a new contact for them."}
                    end

                  {:ok, _} ->
                    {:ok, "No contacts were found for '#{query}' in HubSpot, and I didn't find any emails from this person either. If you have an email address for them, I can create a new contact. Otherwise, you might want to check if the name is spelled correctly or try searching with a different variation."}

                  {:error, _} ->
                    {:ok, "No contacts were found for '#{query}'. If you have an email address for this person, I can create a new contact for them. Just provide the email address."}
                end
              end

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
        # If args["body"] is a JSON string, parse and merge it into args
        args =
          case Map.get(args, "body") do
            body when is_binary(body) ->
              case Jason.decode(body) do
                {:ok, body_map} -> Map.merge(args, body_map)
                _ -> args
              end
            _ -> args
          end
        # Enhanced: recognize a wide range of phrasings and extract info from any message
        email = Map.get(args, "email") || Map.get(args, :email) || extract_email_from_query(user_message)
        name = Map.get(args, "name") || Map.get(args, :name) || extract_name_from_query(user_message)
        first_name = Map.get(args, "first_name") || Map.get(args, :first_name) || (name && String.split(name, " ") |> List.first() || "")
        last_name = Map.get(args, "last_name") || Map.get(args, :last_name) || (name && String.split(name, " ") |> Enum.drop(1) |> Enum.join(" ") || "")
        company = Map.get(args, "company") || Map.get(args, :company) || extract_company_from_query(user_message)
        phone = Map.get(args, "phone") || Map.get(args, :phone) || extract_phone_from_query(user_message)

        cond do
          is_nil(email) or email == "" ->
            {:ask_user, "To create a contact, please provide their email address."}
          is_nil(first_name) or first_name == "" ->
            {:ask_user, "To create a contact, please provide their first name."}
          true ->
            contact_data = %{
              "email" => email,
              "first_name" => first_name,
              "last_name" => last_name,
              "company" => company,
              "phone" => phone
            }
            case HubSpot.create_contact(user, contact_data) do
              {:ok, message} -> {:ok, "Contact created: #{first_name} #{last_name} (#{email})"}
              {:error, reason} -> {:error, "Failed to create contact: #{reason}"}
            end
        end

      "add_note" ->
        contact_email = Map.get(args, "contact_email") || Map.get(args, :contact_email)
        note_content = Map.get(args, "note_content") || Map.get(args, :note_content)

        case HubSpot.add_note(user, contact_email, note_content) do
          {:ok, message} -> {:ok, message}
          {:error, reason} -> {:error, "Failed to add note: #{reason}"}
        end
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

                start_time =
                  get_in(event, ["start", "dateTime"]) || get_in(event, ["start", "date"]) ||
                    "(no time)"

                "• #{summary} at #{start_time}"
              end)
              |> Enum.join("\n")

            {:ok, "Your meetings/events today:\n\n" <> event_list}

          {:ok, _} ->
            {:ask_user,
             "I couldn't find any meetings or events today in your Google Calendar. Would you like me to check your emails or HubSpot for meeting-related information?"}

          {:error, reason} ->
            {:error, "Failed to fetch today's meetings: #{reason}"}
        end

      String.contains?(action_lower, "contact") or String.contains?(action_lower, "person") ->
        execute_contact_action(user, "search", args)

      true ->
        {:ask_user,
         "Could you clarify your request? For example, do you want to see your calendar events, HubSpot meetings, emails, or something else?"}
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

  # Extract email from string
  defp extract_email_from_string(string) when is_binary(string) do
    case Regex.run(~r/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/, string) do
      [email] -> email
      _ -> nil
    end
  end
  defp extract_email_from_string(_), do: nil

  # Format contact list for display
  defp format_contact_list(contacts) do
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
            trigger_desc =
              case instruction.trigger_type do
                "email_received" -> "when emails are received"
                "calendar_event_created" -> "when calendar events are created"
                "hubspot_contact_created" -> "when HubSpot contacts are created"
                _ -> "when triggered"
              end

            "• #{instruction.instruction} (#{trigger_desc})"
          end)
          |> Enum.join("\n")

        {:ok,
         "You have #{length(instructions)} active ongoing instructions:\n\n#{instruction_list}"}

      {:ok, []} ->
        {:ok,
         "You don't have any active ongoing instructions. You can create them by telling me things like 'When I get an email from someone not in HubSpot, automatically add them to HubSpot' or 'When I create a calendar event, send an email to attendees'."}

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
      nil ->
        false

      account ->
        (account.access_token != nil and account.access_token != "") or
          (user.google_access_token != nil and user.google_access_token != "")
    end
  end

  defp has_gmail_access?(user) do
    # Allow if any Google account with a token and any gmail-related scope
    case AdvisorAi.Accounts.get_user_google_account(user.id) do
      nil ->
        false

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
        nil ->
          false

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
      (String.contains?(message_lower, "when i create") and
         String.contains?(message_lower, "calendar")) or
          (String.contains?(message_lower, "when i add") and
             String.contains?(message_lower, "event")) ->
        parse_calendar_instruction(message)

      # HubSpot-related instructions
      (String.contains?(message_lower, "when i create") and
         String.contains?(message_lower, "contact")) or
          (String.contains?(message_lower, "when someone") and
             String.contains?(message_lower, "hubspot")) ->
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
        {:ok,
         %{
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
        {:ok,
         %{
           trigger_type: "email_received",
           instruction: message,
           conditions: %{
             "auto_reply" => true
           }
         }}

      # Generic email instruction
      true ->
        {:ok,
         %{
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
        {:ok,
         %{
           trigger_type: "calendar_event_created",
           instruction: message,
           conditions: %{
             "notify_attendees" => true
           }
         }}

      # Generic calendar instruction
      true ->
        {:ok,
         %{
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
        {:ok,
         %{
           trigger_type: "hubspot_contact_created",
           instruction: message,
           conditions: %{
             "send_welcome_email" => true
           }
         }}

      # Generic HubSpot instruction
      true ->
        {:ok,
         %{
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
        {:ok,
         %{
           trigger_type: "email_received",
           instruction: message,
           conditions: %{
             "check_hubspot" => true,
             "create_contact_if_missing" => true,
             "add_note" => true
           }
         }}

      String.contains?(message_lower, "email") ->
        {:ok,
         %{
           trigger_type: "email_received",
           instruction: message,
           conditions: %{}
         }}

      String.contains?(message_lower, "calendar") or String.contains?(message_lower, "event") ->
        {:ok,
         %{
           trigger_type: "calendar_event_created",
           instruction: message,
           conditions: %{}
         }}

      String.contains?(message_lower, "contact") or String.contains?(message_lower, "hubspot") ->
        {:ok,
         %{
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
    trigger_description =
      case instruction_data.trigger_type do
        "email_received" -> "when you receive emails"
        "calendar_event_created" -> "when you create calendar events"
        "hubspot_contact_created" -> "when you create HubSpot contacts"
        _ -> "when triggered"
      end

    confirmation = "Perfect! I've saved your instruction and will remember to #{instruction_data.instruction} #{trigger_description}. You can manage all your automated instructions in Settings > Instructions."

    # Suggest next logical step based on instruction
    suggestion =
      cond do
        instruction_data.trigger_type == "hubspot_contact_created" and String.contains?(String.downcase(instruction_data.instruction), "send them an email") ->
          "Would you like to create a new contact now so I can send them a welcome email? Please provide their name and email."
        instruction_data.trigger_type == "email_received" and String.contains?(String.downcase(instruction_data.instruction), "appointment") ->
          "Would you like to schedule an appointment now? Please provide the contact's name and email."
        instruction_data.trigger_type == "calendar_event_created" and String.contains?(String.downcase(instruction_data.instruction), "notify attendees") ->
          "Would you like to create a calendar event now and notify attendees? Please provide the event details."
        true ->
          "If you'd like to try out this automation now, just let me know what you'd like to do next!"
      end

    confirmation <> "\n\n" <> suggestion
  end

  defp format_datetime_for_chat(nil), do: "(No time)"

  defp format_datetime_for_chat(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _} ->
        # Format as local time for better readability
        datetime
        |> DateTime.shift_zone!("America/New_York")
        |> Calendar.strftime("%B %d, %Y at %I:%M %p")

      _ ->
        datetime_string
    end
  end

  defp format_availability_times(availability) do
    case availability do
      times when is_list(times) and length(times) > 0 ->
        formatted_times =
          Enum.map(times, fn slot ->
            start_time = format_datetime_for_chat(slot["start"])
            end_time = format_datetime_for_chat(slot["end"])
            "• #{start_time} - #{end_time}"
          end)
          |> Enum.join("\n")

        "Available times:\n#{formatted_times}"

      _ ->
        "No available times found for the requested period."
    end
  end

  # Helper functions for contact creation
  defp extract_email_from_query(query) do
    # Look for email pattern in the query
    case Regex.run(~r/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/, query) do
      [email | _] -> email
      nil -> nil
    end
  end

    defp extract_name_from_query(query) do
    # Remove email from query to get name
    name = Regex.replace(~r/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/, query, "")
    name = String.trim(name)

    if name == "" do
      # If no name found, try to extract from email
      case extract_email_from_query(query) do
        email when is_binary(email) ->
          email |> String.split("@") |> List.first() |> String.replace(".", " ") |> String.replace("_", " ")
        nil ->
          "Unknown"
      end
    else
      name
    end
  end

  defp parse_name(name) do
    # Split name into first and last name
    case String.split(name, " ", parts: 2) do
      [first, last] -> {first, last}
      [first] when first != "" -> {first, ""}
      _ -> {"", ""}
    end
  end

    # Get recent context for LLM decision making
  defp get_recent_context_for_llm(context) do
    # Extract relevant context from recent conversations and user patterns
    recent_context_parts = []

    # Add conversation context if available
    if context.conversation && context.conversation != "No recent conversation" do
      recent_context_parts = recent_context_parts ++ ["Recent conversation available"]
    end

    # Add user patterns based on available services
    if context.user.gmail_available do
      recent_context_parts = recent_context_parts ++ ["User has Gmail access"]
    end

    if context.user.calendar_available do
      recent_context_parts = recent_context_parts ++ ["User has Calendar access"]
    end

    if context.user.hubspot_connected do
      recent_context_parts = recent_context_parts ++ ["User has HubSpot access"]
    end

    # Add time-based context
    current_hour = DateTime.utc_now().hour
    time_context = cond do
      current_hour < 12 -> "Morning hours"
      current_hour < 17 -> "Afternoon hours"
      current_hour < 21 -> "Evening hours"
      true -> "Late evening hours"
    end

    recent_context_parts = recent_context_parts ++ [time_context]

    # Join context parts
    if Enum.empty?(recent_context_parts) do
      "No recent context available"
    else
      Enum.join(recent_context_parts, ", ")
    end
  end

  # Enhanced helper functions for intelligent action execution
  defp get_user_services_status(user) do
    services = []
    services = if has_gmail_access?(user), do: services ++ ["Gmail"], else: services
    services = if has_calendar_access?(user), do: services ++ ["Calendar"], else: services
    services = if has_hubspot_connection?(user), do: services ++ ["HubSpot"], else: services

    if Enum.empty?(services) do
      "No services connected"
    else
      Enum.join(services, ", ")
    end
  end

  defp extract_json_from_response(response) do
    case response do
      %{"choices" => [%{"message" => %{"content" => content}} | _]} ->
        # Try to extract JSON from the content
        case Regex.run(~r/\{.*\}/s, content) do
          [json_str] ->
            case Jason.decode(json_str) do
              {:ok, parsed} -> {:ok, parsed}
              {:error, _} -> {:error, "Invalid JSON"}
            end
          nil ->
            {:error, "No JSON found"}
        end
      _ ->
        {:error, "Unexpected response format"}
    end
  end

  # Enhanced Gmail search with intelligent query handling
  defp execute_enhanced_gmail_search(user, args) do
    query = Map.get(args, "query", "")
    max_results = Map.get(args, "max_results", 10)

    # Use LLM to enhance the search query if it's ambiguous
    enhanced_query = enhance_search_query(query)

    case Gmail.search_emails(user, enhanced_query) do
      {:ok, emails} ->
        emails_to_show = Enum.take(emails, max_results)

        # Provide intelligent summary
        summary = generate_email_search_summary(emails_to_show, query)

        email_list =
          Enum.map(emails_to_show, fn email ->
            "• #{email.subject} (from: #{email.from})"
          end)
          |> Enum.join("\n")

        {:ok, "#{summary}\n\n#{email_list}"}

      {:error, reason} ->
        # Suggest alternatives if search fails
        suggestions = suggest_email_search_alternatives(query)
        {:error, "Failed to search emails: #{reason}. #{suggestions}"}
    end
  end

  # Enhanced Gmail send with intelligent composition
  defp execute_enhanced_gmail_send(user, args) do
    to = Map.get(args, "to") || Map.get(args, :to)
    subject = Map.get(args, "subject") || Map.get(args, :subject)
    body = Map.get(args, "body") || Map.get(args, :body)

    # Validate and enhance the email
    case validate_and_enhance_email(to, subject, body) do
      {:ok, enhanced_email} ->
        case Gmail.send_email(user, enhanced_email.to, enhanced_email.subject, enhanced_email.body) do
          {:ok, _} ->
            # Suggest follow-up actions
            follow_up = suggest_email_follow_ups(enhanced_email)
            {:ok, "Email sent successfully to #{enhanced_email.to}. #{follow_up}"}
          {:error, reason} ->
            {:error, "Failed to send email: #{reason}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Enhanced calendar list with intelligent filtering
  defp execute_enhanced_calendar_list(user, args) do
    date = Map.get(args, "date") || Date.utc_today() |> Date.to_iso8601()
    max_results = Map.get(args, "max_results", 10)

    case Calendar.get_events(user, "#{date}T00:00:00Z", "#{date}T23:59:59Z") do
      {:ok, events} ->
        events_to_show = Enum.take(events, max_results)

        # Provide intelligent summary
        summary = generate_calendar_summary(events_to_show, date)

        event_list =
          Enum.map(events_to_show, fn event ->
            summary = Map.get(event, "summary", "(no title)")
            start_time = get_in(event, ["start", "dateTime"]) || get_in(event, ["start", "date"]) || "(no time)"
            "• #{summary} at #{start_time}"
          end)
          |> Enum.join("\n")

        {:ok, "#{summary}\n\n#{event_list}"}

      {:error, reason} ->
        {:error, "Failed to list calendar events: #{reason}"}
    end
  end

  # Enhanced calendar create with intelligent scheduling
  defp execute_enhanced_calendar_create(user, args) do
    summary = Map.get(args, "summary") || Map.get(args, :summary)
    start_time = Map.get(args, "start_time") || Map.get(args, :start_time)
    end_time = Map.get(args, "end_time") || Map.get(args, :end_time)

    # Validate and enhance the event
    case validate_and_enhance_event(summary, start_time, end_time) do
      {:ok, enhanced_event} ->
        case Calendar.create_event(user, enhanced_event) do
          {:ok, _} ->
            # Suggest follow-up actions
            follow_up = suggest_event_follow_ups(enhanced_event)
            {:ok, "Calendar event '#{enhanced_event.summary}' created successfully. #{follow_up}"}
          {:error, reason} ->
            {:error, "Failed to create calendar event: #{reason}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Enhanced contact search with intelligent creation
  defp execute_enhanced_contact_search(user, args) do
    query = Map.get(args, "query") || Map.get(args, :query) || ""

    case HubSpot.search_contacts(user, query) do
      {:ok, contacts} when is_list(contacts) and length(contacts) > 0 ->
        contact_list =
          Enum.map(contacts, fn contact ->
            properties = contact["properties"] || %{}
            firstname = properties["firstname"] || ""
            lastname = properties["lastname"] || ""
            email = properties["email"] || ""
            company = properties["company"] || ""

            name = "#{firstname} #{lastname}" |> String.trim()
            name = if name == "", do: "Unknown", else: name

            contact_info = "• #{name}"
            contact_info = if email != "", do: contact_info <> " (#{email})", else: contact_info
            contact_info = if company != "", do: contact_info <> " - #{company}", else: contact_info

            contact_info
          end)
          |> Enum.join("\n")

        {:ok, "Found #{length(contacts)} HubSpot contacts:\n\n#{contact_list}"}

      {:ok, _} ->
        # Try to extract email from query for proactive contact creation
        email = extract_email_from_query(query)
        name = extract_name_from_query(query)

        if email do
          # Automatically create the contact if email is found
          {first_name, last_name} = parse_name(name)
          contact_data = %{
            "email" => email,
            "first_name" => first_name,
            "last_name" => last_name,
            "company" => ""
          }

          case HubSpot.create_contact(user, contact_data) do
            {:ok, _message} ->
              {:ok, "I've automatically created a new HubSpot contact for #{name} (#{email}). The contact has been added to your HubSpot account."}
            {:error, reason} ->
              {:ok, "I found an email address (#{email}) but couldn't create the contact automatically: #{reason}. You can try creating it manually in HubSpot."}
          end
        else
          {:ok, "No contacts were found for '#{query}'. If you have an email address for this person, I can create a new contact for them. Just provide the email address."}
        end

      {:error, reason} ->
        {:error, "Failed to search HubSpot contacts: #{reason}"}
    end
  end

  # Helper functions for enhanced operations
  defp enhance_search_query(query) do
    # Use LLM to enhance ambiguous search queries
    query_length = String.length(query)
    if query_length < 3 do
      # Query is too short, try to expand it
      case OpenRouterClient.chat_completion(
             messages: [
               %{role: "system", content: "You are an expert at enhancing email search queries."},
               %{role: "user", content: "Enhance this email search query to be more specific: '#{query}'"}
             ],
             temperature: 0.1
           ) do
        {:ok, response} ->
          case extract_text_response(response) do
            enhanced when is_binary(enhanced) ->
              enhanced_length = String.length(enhanced)
              if enhanced_length > 3, do: enhanced, else: query
            _ ->
              query
          end
        {:error, _} ->
          query
      end
    else
      query
    end
  end

  defp generate_email_search_summary(emails, query) do
    count = length(emails)
    if count == 0 do
      "No emails found matching '#{query}'"
    else
      "Found #{count} email(s) matching '#{query}'"
    end
  end

  defp suggest_email_search_alternatives(query) do
    "Try searching with different terms or check your spelling."
  end

  defp validate_and_enhance_email(to, subject, body) do
    # Basic validation
    cond do
      is_nil(to) or to == "" ->
        {:error, "Email recipient is required"}

      is_nil(subject) or subject == "" ->
        {:error, "Email subject is required"}

      is_nil(body) or body == "" ->
        {:error, "Email body is required"}

      true ->
        # Enhance the email if needed
        enhanced_subject = if String.length(subject) < 5, do: "Re: #{subject}", else: subject
        enhanced_body = if String.length(body) < 10, do: "#{body}\n\nBest regards", else: body

        {:ok, %{to: to, subject: enhanced_subject, body: enhanced_body}}
    end
  end

  defp suggest_email_follow_ups(email) do
    "Consider adding a calendar reminder or HubSpot note for follow-up."
  end

  defp generate_calendar_summary(events, date) do
    count = length(events)
    if count == 0 do
      "No events scheduled for #{date}"
    else
      "You have #{count} event(s) scheduled for #{date}"
    end
  end

  defp validate_and_enhance_event(summary, start_time, end_time) do
    # Basic validation
    cond do
      is_nil(summary) or summary == "" ->
        {:error, "Event summary is required"}

      is_nil(start_time) or start_time == "" ->
        {:error, "Event start time is required"}

      is_nil(end_time) or end_time == "" ->
        {:error, "Event end time is required"}

      true ->
        # Enhance the event if needed
        enhanced_summary = if String.length(summary) < 3, do: "Meeting: #{summary}", else: summary

        {:ok, %{summary: enhanced_summary, start_time: start_time, end_time: end_time}}
    end
  end

  defp suggest_event_follow_ups(event) do
    "Consider sending calendar invites to attendees or adding notes to HubSpot."
  end

  # Execute tool call with intelligent retry and error handling
  defp execute_tool_call_with_retry(user, tool_call, user_message, context, retry_count \\ 0) do
    max_retries = 2

    case execute_tool_call(user, tool_call) do
      {:ok, result} ->
        {:ok, result}

      {:error, error} when retry_count < max_retries ->
        # Try to intelligently fix the error and retry
        case intelligently_fix_tool_call_error(user, tool_call, error, user_message, context) do
          {:ok, fixed_tool_call} ->
            execute_tool_call_with_retry(user, fixed_tool_call, user_message, context, retry_count + 1)

          {:error, _} ->
            # If we can't fix it, try alternative approaches
            case try_alternative_approach(user, tool_call, error, user_message, context) do
              {:ok, result} -> {:ok, result}
              {:error, final_error} -> {:error, "Failed after #{retry_count + 1} attempts: #{final_error}"}
            end
        end

      {:error, error} ->
        {:error, error}

      other ->
        other
    end
  end

  # Intelligently fix tool call errors
  defp intelligently_fix_tool_call_error(user, tool_call, error, user_message, context) do
    # Use LLM to analyze the error and suggest fixes
    error_analysis_prompt = """
    Analyze this tool call error and suggest a fix:

    Tool Call: #{inspect(tool_call)}
    Error: #{error}
    User Message: #{user_message}
    Context: #{inspect(context)}

    Suggest a fixed tool call that addresses the error. Return JSON in this format:
    {
      "fixed_tool_call": {fixed tool call object},
      "reasoning": "explanation of the fix"
    }
    """

    case OpenRouterClient.chat_completion(
           messages: [
             %{role: "system", content: "You are an expert at fixing tool call errors."},
             %{role: "user", content: error_analysis_prompt}
           ],
           temperature: 0.1
         ) do
      {:ok, response} ->
        case extract_json_from_response(response) do
          {:ok, %{"fixed_tool_call" => fixed_tool_call}} ->
            {:ok, fixed_tool_call}
          {:error, _} ->
            {:error, "Could not parse fix suggestion"}
        end

      {:error, _} ->
        {:error, "Could not analyze error"}
    end
  end

  # Try alternative approaches when the original fails
  defp try_alternative_approach(user, tool_call, error, user_message, context) do
    # Use LLM to suggest alternative approaches
    alternative_prompt = """
    The original tool call failed. Suggest an alternative approach:

    Original Tool Call: #{inspect(tool_call)}
    Error: #{error}
    User Message: #{user_message}
    Context: #{inspect(context)}

    Suggest an alternative tool call or approach. Return JSON in this format:
    {
      "alternative_tool_call": {alternative tool call object},
      "reasoning": "explanation of the alternative"
    }
    """

    case OpenRouterClient.chat_completion(
           messages: [
             %{role: "system", content: "You are an expert at finding alternative approaches when tools fail."},
             %{role: "user", content: alternative_prompt}
           ],
           temperature: 0.1
         ) do
      {:ok, response} ->
        case extract_json_from_response(response) do
          {:ok, %{"alternative_tool_call" => alternative_tool_call}} ->
            execute_tool_call(user, alternative_tool_call)
          {:error, _} ->
            {:error, "Could not parse alternative suggestion"}
        end

      {:error, _} ->
        {:error, "Could not suggest alternative"}
    end
  end

  # Process tool call results intelligently
  defp process_tool_call_results(results, user_message, context) do
    # Analyze results and provide intelligent summary
    {successful_results, failed_results} =
      Enum.split_with(results, fn
        {:ok, _} -> true
        _ -> false
      end)

    cond do
      # All successful
      Enum.empty?(failed_results) ->
        successful_results
        |> Enum.map(fn {:ok, result} -> result end)
        |> Enum.join("\n\n")

      # Some failures
      length(failed_results) < length(results) ->
        success_text =
          successful_results
          |> Enum.map(fn {:ok, result} -> result end)
          |> Enum.join("\n\n")

        failure_text =
          failed_results
          |> Enum.map(fn
            {:error, error} -> "⚠️ #{error}"
            other -> "⚠️ Unexpected result: #{inspect(other)}"
          end)
          |> Enum.join("\n")

        "#{success_text}\n\n#{failure_text}"

      # All failed
      true ->
        # Try to provide helpful suggestions
        suggestions = generate_helpful_suggestions(user_message, failed_results, context)

        failure_text =
          failed_results
          |> Enum.map(fn
            {:error, error} -> "❌ #{error}"
            other -> "❌ Unexpected result: #{inspect(other)}"
          end)
          |> Enum.join("\n")

        "#{failure_text}\n\n💡 Suggestions: #{suggestions}"
    end
  end

  # Generate helpful suggestions when all tool calls fail
  defp generate_helpful_suggestions(user_message, failed_results, context) do
    # Use LLM to generate helpful suggestions
    suggestion_prompt = """
    The user's request failed. Generate helpful suggestions:

    User Message: #{user_message}
    Failed Results: #{inspect(failed_results)}
    Context: #{inspect(context)}

    Provide 2-3 helpful suggestions for what the user could try instead.
    """

    case OpenRouterClient.chat_completion(
           messages: [
             %{role: "system", content: "You are an expert at providing helpful suggestions when requests fail."},
             %{role: "user", content: suggestion_prompt}
           ],
           temperature: 0.1
         ) do
      {:ok, response} ->
        case extract_text_response(response) do
          suggestions when is_binary(suggestions) ->
            suggestions
          _ ->
            "Try rephrasing your request or check that your accounts are properly connected."
        end

      {:error, _} ->
        "Try rephrasing your request or check that your accounts are properly connected."
    end
  end

  # Helper functions for enhanced extraction
  defp extract_company_from_query(query) do
    # Look for 'company' or 'at [company]' in the query
    case Regex.run(~r/(?:company|at) ([A-Za-z0-9 .,&'-]+)/, query) do
      [_, company] -> String.trim(company)
      _ -> ""
    end
  end

  defp extract_phone_from_query(query) do
    # Look for phone numbers in the query
    case Regex.run(~r/(\+?\d[\d .-]{7,}\d)/, query) do
      [_, phone] -> String.trim(phone)
      _ -> ""
    end
  end
end
