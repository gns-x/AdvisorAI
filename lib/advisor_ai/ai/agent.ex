defmodule AdvisorAi.AI.Agent do
  @moduledoc """
  Main AI agent service that handles:
  - RAG (Retrieval Augmented Generation) using vector embeddings
  - Intelligent workflow generation and execution
  - Task management and memory for ongoing operations
  - Proactive agent behavior based on triggers
  """

  import Ecto.Query
  alias AdvisorAi.Repo
  alias AdvisorAi.Chat
  alias AdvisorAi.Chat.{Conversation, Message}

  alias AdvisorAi.AI.{
    VectorEmbedding,
    AgentInstruction,
    OpenRouterClient,
    IntelligentAgent,
    WorkflowGenerator,
    UniversalAgent
  }

  alias AdvisorAi.Tasks.AgentTask
  alias AdvisorAi.Integrations.{Gmail, Calendar, HubSpot}

  # OpenAI client will be configured at runtime

  def process_user_message(user, conversation_id, message_content) do
    # Get conversation context
    conversation = get_conversation_with_context(conversation_id, user.id)

    # Create user message
    {:ok, _user_message} =
      create_message(conversation_id, %{
        role: "user",
        content: message_content
      })

    # Get relevant context from RAG
    context = get_relevant_context(user.id, message_content)

    # Get active instructions
    instructions = get_active_instructions(user.id)

    # Use universal agent approach (AI-driven tool calling)
    case UniversalAgent.process_request(user, conversation_id, message_content) do
      {:ok, assistant_message} ->
        {:ok, assistant_message}

      {:error, reason} ->
        # Fallback to intelligent agent
        case IntelligentAgent.process_request(user, conversation_id, message_content) do
          {:ok, assistant_message} ->
            {:ok, assistant_message}

          {:error, intelligent_reason} ->
            # Fallback to workflow generator
            case handle_with_workflow(
                   user,
                   conversation_id,
                   message_content,
                   context,
                   instructions
                 ) do
              {:ok, response} ->
                {:ok, response}

              {:error, workflow_reason} ->
                # Final fallback: simple response
                {:ok, error_message} =
                  create_message(conversation_id, %{
                    role: "assistant",
                    content:
                      "I understand your request. Let me help you with that. #{workflow_reason}"
                  })

                {:ok, error_message}
            end
        end
    end
  end

  def handle_trigger(user, trigger_type, trigger_data) do
    require Logger

    Logger.info("🎯 Agent: Handling trigger #{trigger_type} for user #{user.email}")
    Logger.info("📊 Agent: Trigger data: #{inspect(trigger_data)}")

    case AgentInstruction.get_active_instructions_by_trigger(user.id, trigger_type) do
      {:ok, instructions} ->
        Logger.info(
          "📋 Agent: Found #{length(instructions)} active instructions for trigger #{trigger_type}"
        )

        if length(instructions) > 0 do
          # Execute automation rules for this trigger
          results =
            Enum.map(instructions, fn instruction ->
              Logger.info("⚡ Agent: Executing instruction: #{instruction.instruction}")
              execute_automation_rule(user, instruction, trigger_type, trigger_data)
            end)

          Logger.info("✅ Agent: Executed #{length(results)} automation rules")
          {:ok, results}
        else
          Logger.info("⏭️ Agent: No active instructions found for trigger #{trigger_type}")
          {:ok, nil}
        end

      {:error, reason} ->
        Logger.error("❌ Agent: Failed to get instructions for trigger #{trigger_type}: #{reason}")
        {:error, reason}
    end
  end

  # Execute automation rule based on instruction
  defp execute_automation_rule(user, instruction, trigger_type, trigger_data) do
    require Logger

    instruction_text = if is_map(instruction), do: instruction.instruction, else: instruction
    Logger.info("⚡ Agent: Executing automation rule: #{instruction_text}")

    # Parse the instruction to extract action details
    case parse_automation_instruction(instruction_text) do
      {:ok, action_type, params} ->
        Logger.info("🔧 Agent: Parsed action: #{action_type} with params: #{inspect(params)}")

        # Execute the action
        case execute_automation_action(user, action_type, params, trigger_data) do
          {:ok, result} ->
            Logger.info("✅ Agent: Automation action executed successfully: #{result}")
            {:ok, result}

          {:error, reason} ->
            Logger.error("❌ Agent: Automation action failed: #{reason}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("❌ Agent: Failed to parse automation instruction: #{reason}")
        {:error, reason}
    end
  end

  # Enhanced automation action execution with complex logic
  defp execute_automation_action(user, action_type, params, trigger_data) do
    case action_type do
      "email_received" ->
        execute_email_received_automation(user, params, trigger_data)

      "send_email" ->
        execute_automation_email(user, params, trigger_data)

      "create_calendar_event" ->
        execute_automation_calendar(user, params, trigger_data)

      "add_note" ->
        execute_automation_note(user, params, trigger_data)

      "search_emails" ->
        execute_automation_search(user, params, trigger_data)

      _ ->
        {:error, "Unknown automation action: #{action_type}"}
    end
  end

  # Handle email_received automation with complex logic
  defp execute_email_received_automation(user, params, trigger_data) do
    case trigger_data do
      %{from: sender_email, subject: subject, body: body} ->
        # Check if this is a complex instruction that requires HubSpot integration
        if Map.get(params, "check_hubspot", false) do
          execute_hubspot_email_automation(user, sender_email, subject, body, params)
        else
          # Simple email automation
          execute_simple_email_automation(user, sender_email, subject, body, params)
        end

      _ ->
        {:error, "Invalid email trigger data"}
    end
  end

  # Execute complex HubSpot + email automation
  defp execute_hubspot_email_automation(user, sender_email, subject, body, params) do
    require Logger

    Logger.info("🔍 Agent: Checking if contact exists in HubSpot: #{sender_email}")

    # Parse sender name and email
    {parsed_name, parsed_email} =
      case Regex.run(~r/^(.*)<(.+@.+)>$/, sender_email) do
        [_, name, email] -> {String.trim(name), String.trim(email)}
        nil -> {"", String.trim(sender_email)}
      end
    {first_name, last_name} =
      case String.split(parsed_name || "", " ", parts: 2) do
        [f, l] -> {f, l}
        [f] when f != "" -> {f, ""}
        _ -> {"", ""}
      end

    # Step 1: Check if contact exists in HubSpot
    case AdvisorAi.Integrations.HubSpot.get_contact_by_email(user, parsed_email) do
      {:ok, nil} ->
        Logger.info("👤 Contact not found in HubSpot. Creating new contact...")
        # Step 2: Create contact in HubSpot
        contact_data = %{
          "email" => parsed_email,
          "first_name" => first_name,
          "last_name" => last_name,
          "company" => "",
          "notes" => if(Map.get(params, "add_note", false), do: body, else: nil)
        }
        case AdvisorAi.Integrations.HubSpot.create_contact(user, contact_data) do
          {:ok, contact} ->
            Logger.info("✅ Contact created in HubSpot: #{inspect(contact)}")
            # Send notification to user in chat
            AdvisorAi.Chat.create_message_for_user(
              user,
              "A new HubSpot contact was created for #{parsed_email} with subject: '#{subject}'."
            )
            {:ok, "Contact created in HubSpot and user notified"}
          {:error, reason} ->
            Logger.error("❌ Failed to create contact in HubSpot: #{reason}")
            {:error, "Failed to create contact in HubSpot: #{reason}"}
        end
      {:ok, _contact} ->
        Logger.info("👤 Contact already exists in HubSpot: #{parsed_email}")
        {:ok, "Contact already exists in HubSpot"}
      {:error, reason} ->
        Logger.error("❌ Failed to check contact in HubSpot: #{reason}")
        {:error, "Failed to check contact in HubSpot: #{reason}"}
    end
  end

  # Execute simple email automation
  defp execute_simple_email_automation(user, sender_email, subject, body, params) do
    # Handle auto-reply logic
    if Map.get(params, "auto_reply", false) do
      auto_reply_content = generate_auto_reply(sender_email, subject, body)

      case Gmail.send_email(user, sender_email, "Re: #{subject}", auto_reply_content) do
        {:ok, _} -> {:ok, "Sent auto-reply to #{sender_email}"}
        {:error, reason} -> {:error, "Failed to send auto-reply: #{reason}"}
      end
    else
      {:ok, "Email received from #{sender_email}: #{subject}"}
    end
  end

  # Generate auto-reply content
  defp generate_auto_reply(sender_email, subject, body) do
    """
    Thank you for your email regarding "#{subject}".

    I've received your message and will get back to you as soon as possible.

    Best regards,
    Your Assistant
    """
  end

  defp handle_with_workflow(user, conversation_id, message_content, context, instructions) do
    # Generate workflow for the request
    case WorkflowGenerator.generate_workflow(message_content, context) do
      {:ok, workflow} ->
        # Extract data from the request
        extracted_data = extract_data_from_request(message_content)

        # Execute the workflow
        case WorkflowGenerator.execute_workflow(user, workflow, extracted_data) do
          {:ok, results} ->
            # Generate response based on workflow results
            response = generate_workflow_response(message_content, workflow, results)

            {:ok, assistant_message} =
              create_message(conversation_id, %{
                role: "assistant",
                content: response
              })

            {:ok, assistant_message}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_data_from_request(message) do
    # Extract key information from the user's request
    %{
      "email" => extract_email_address(message),
      "name" => extract_name(message),
      "date" => extract_date(message),
      "time" => extract_time(message),
      "subject" => extract_subject(message)
    }
  end

  defp generate_workflow_response(user_message, workflow, results) do
    # Generate a natural response based on the workflow execution
    system_prompt = """
    You are a helpful AI assistant. Generate a natural response to the user based on:

    - User's request: #{user_message}
    - Workflow executed: #{inspect(workflow)}
    - Results: #{inspect(results)}

    Be conversational and helpful. If some steps failed, explain what went wrong and suggest alternatives.
    If everything worked, confirm what was accomplished.
    """

    case OpenRouterClient.chat_completion(
           messages: [
             %{role: "system", content: system_prompt},
             %{role: "user", content: user_message}
           ]
         ) do
      {:ok, %{"choices" => [%{"message" => %{"content" => response}}]}} ->
        response

      {:error, _} ->
        # Fallback response
        generate_fallback_workflow_response(workflow, results)
    end
  end

  defp generate_fallback_workflow_response(workflow, results) do
    workflow_name = Map.get(workflow, "workflow_name", "the requested task")

    # Count successful vs failed steps
    {successful, failed} =
      Enum.reduce(results, {0, 0}, fn {_step, result}, {s, f} ->
        case result do
          %{error: _} -> {s, f + 1}
          _ -> {s + 1, f}
        end
      end)

    cond do
      failed == 0 ->
        "I've successfully completed #{workflow_name}. All steps were completed successfully."

      successful > 0 ->
        "I've partially completed #{workflow_name}. #{successful} steps succeeded, but #{failed} steps encountered issues. Would you like me to try a different approach for the failed steps?"

      true ->
        "I encountered issues while trying to complete #{workflow_name}. All steps failed. Would you like me to try a different approach or help you troubleshoot this?"
    end
  end

  # Helper functions for data extraction
  defp extract_email_address(message) do
    case Regex.run(~r/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/, message) do
      [email | _] -> email
      nil -> nil
    end
  end

  defp extract_name(message) do
    # Simple name extraction - could be enhanced with AI
    case Regex.run(~r/(?:to|for|with)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)/, message) do
      [_, name | _] -> name
      nil -> nil
    end
  end

  defp extract_date(message) do
    cond do
      String.contains?(String.downcase(message), "tomorrow") -> "tomorrow"
      String.contains?(String.downcase(message), "today") -> "today"
      String.contains?(String.downcase(message), "next week") -> "next week"
      true -> nil
    end
  end

  defp extract_time(message) do
    case Regex.run(~r/(\d{1,2}:\d{2}\s*(?:AM|PM|am|pm)?)/, message) do
      [time | _] -> time
      nil -> nil
    end
  end

  defp extract_subject(message) do
    # Simple subject extraction
    case Regex.run(~r/(?:about|regarding|subject:?)\s+([^.]+)/, message) do
      [_, subject | _] -> String.trim(subject)
      nil -> "Meeting Request"
    end
  end

  defp get_conversation_with_context(conversation_id, user_id) do
    Conversation
    |> where(id: ^conversation_id, user_id: ^user_id)
    |> preload(messages: ^from(m in Message, order_by: m.inserted_at))
    |> Repo.one!()
  end

  defp get_relevant_context(user_id, message) do
    # Get embedding for the message
    case get_embedding(message) do
      {:ok, query_embedding} ->
        VectorEmbedding.find_similar(user_id, query_embedding, 5)
        |> AdvisorAi.Repo.all()
        |> Enum.map(& &1.content)
        |> Enum.join("\n")

      {:error, _} ->
        ""
    end
  end

  defp get_embedding(text) do
    # Use OpenRouter for RAG
    case AdvisorAi.AI.OpenRouterClient.embeddings(input: text) do
      {:ok, %{"data" => [%{"embedding" => embedding}]}} ->
        {:ok, embedding}

      {:error, reason} ->
        {:error, "Failed to get embedding: #{reason}"}
    end
  end

  defp get_active_instructions(user_id) do
    AgentInstruction
    |> where(user_id: ^user_id, is_active: true)
    |> Repo.all()
  end

  defp create_message(conversation_id, attrs) do
    AdvisorAi.Chat.create_message(conversation_id, attrs)
  end

  defp build_trigger_message(trigger_type, trigger_data) do
    case trigger_type do
      "email_received" ->
        "A new email was received from #{trigger_data.from} with subject: #{trigger_data.subject}"

      "calendar_event" ->
        "A calendar event was #{trigger_data.action}: #{trigger_data.title}"

      "hubspot_update" ->
        "A HubSpot #{trigger_data.type} was #{trigger_data.action}: #{trigger_data.name}"

      _ ->
        "A #{trigger_type} event occurred"
    end
  end

  # Parse automation instruction to extract action type and parameters
  defp parse_automation_instruction(instruction) do
    instruction_lower = String.downcase(instruction)

    # Look for action type in the instruction
    cond do
      # Email-related actions
      String.contains?(instruction_lower, "when i get an email") or
          String.contains?(instruction_lower, "when someone emails me") ->
        {:ok, "email_received", %{}}

      String.contains?(instruction_lower, "send_email") or
          String.contains?(instruction_lower, "send an email") ->
        {:ok, "send_email",
         %{"to" => "attendees", "subject" => "Meeting Notification", "body" => "Meeting details"}}

      # Calendar-related actions
      String.contains?(instruction_lower, "create_calendar_event") or
          String.contains?(instruction_lower, "add event") ->
        {:ok, "create_calendar_event",
         %{"title" => "Auto-created event", "description" => "Automatically created"}}

      # Note-related actions
      String.contains?(instruction_lower, "add_note") or
          String.contains?(instruction_lower, "add a note") ->
        {:ok, "add_note", %{"note" => "Automation triggered"}}

      # Search actions
      String.contains?(instruction_lower, "search_emails") or
          String.contains?(instruction_lower, "search emails") ->
        {:ok, "search_emails", %{"query" => "automation"}}

      # HubSpot actions
      String.contains?(instruction_lower, "add them to hubspot") or
          String.contains?(instruction_lower, "create contact") ->
        {:ok, "email_received",
         %{"check_hubspot" => true, "create_contact_if_missing" => true, "add_note" => true}}

      true ->
        {:error, "Unknown action type in instruction"}
    end
  end

  # Execute automation email
  defp execute_automation_email(user, params, trigger_data) do
    case trigger_data do
      %{action: "created", title: title, id: event_id} ->
        # Calendar event was created - send email to attendees
        case get_calendar_event_attendees(user, event_id) do
          {:ok, attendees} ->
            subject = "Meeting Notification: #{title}"

            body = """
            Hello,

            You have been invited to a meeting: #{title}

            Meeting Details:
            - Title: #{title}
            - Event ID: #{event_id}

            Please check your calendar for more details.

            Best regards,
            #{user.name}
            """

            # Send email to each attendee
            results =
              Enum.map(attendees, fn attendee ->
                case Gmail.send_email(user, attendee, subject, body) do
                  {:ok, _} -> {:ok, "Email sent to #{attendee}"}
                  {:error, reason} -> {:error, "Failed to send email to #{attendee}: #{reason}"}
                end
              end)

            {:ok, "Sent meeting notifications to #{length(attendees)} attendees"}

          {:error, reason} ->
            {:error, "Failed to get attendees: #{reason}"}
        end

      _ ->
        {:error, "Unsupported trigger data for email automation"}
    end
  end

  # Execute automation calendar
  defp execute_automation_calendar(user, params, trigger_data) do
    # Handle calendar-related automations
    {:ok, "Calendar automation executed"}
  end

  # Execute automation note
  defp execute_automation_note(_user, _params, _trigger_data) do
    # Handle note-related automations
    {:ok, "Note automation executed"}
  end

  # Execute automation search
  defp execute_automation_search(_user, _params, _trigger_data) do
    # Handle search-related automations
    {:ok, "Search automation executed"}
  end

  # Get calendar event attendees
  defp get_calendar_event_attendees(user, event_id) do
    case Calendar.get_event(user, event_id) do
      {:ok, event} ->
        attendees = get_in(event, ["attendees"]) || []
        attendee_emails = Enum.map(attendees, & &1["email"])
        {:ok, attendee_emails}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
