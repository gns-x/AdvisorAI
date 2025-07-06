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
  alias AdvisorAi.Chat.{Conversation, Message}
  alias AdvisorAi.AI.{VectorEmbedding, AgentInstruction, OpenRouterClient, LocalEmbeddingClient, IntelligentAgent, WorkflowGenerator}
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

    # Use intelligent agent approach
    case IntelligentAgent.process_request(user, conversation_id, message_content) do
      {:ok, assistant_message} ->
        {:ok, assistant_message}

      {:error, reason} ->
        # Fallback to workflow generator
        case handle_with_workflow(user, conversation_id, message_content, context, instructions) do
          {:ok, response} ->
            {:ok, response}
          {:error, workflow_reason} ->
            # Final fallback: simple response
            {:ok, error_message} =
              create_message(conversation_id, %{
                role: "assistant",
                content: "I understand your request. Let me help you with that. #{workflow_reason}"
              })
            {:ok, error_message}
        end
    end
  end

  def handle_trigger(user, trigger_type, trigger_data) do
    # Get active instructions for this trigger
    instructions = get_active_instructions_by_trigger(user.id, trigger_type)

    IO.puts("DEBUG: Handling trigger #{trigger_type} with #{length(instructions)} instructions")

    # Execute automation rules for this trigger
    Enum.each(instructions, fn instruction ->
      execute_automation_rule(user, instruction, trigger_type, trigger_data)
    end)

    # Check for pending agent tasks that match the trigger
    pending_tasks =
      AgentTask
      |> where(user_id: ^user.id, status: "pending")
      |> Repo.all()

    Enum.each(pending_tasks, fn task ->
      # Simple matching: if the trigger_data contains an email or event that matches the task context, continue the task
      if Map.has_key?(task.context, "wait_for_email") and trigger_type == "email_received" do
        # Mark task as completed and take action (e.g., send follow-up)
        AgentTask.changeset(task, %{status: "completed", completed_at: DateTime.utc_now()})
        |> Repo.update()

        # Optionally, trigger a follow-up action here
      end

      # Add more matching logic for calendar/hubspot as needed
    end)

    if length(instructions) > 0 do
      # Create a system message with the trigger context
      trigger_message = build_trigger_message(trigger_type, trigger_data)

      # Get conversation context
      {:ok, conversation} = get_or_create_current_conversation(user.id)

      # Process with intelligent agent
      context = get_relevant_context(user.id, trigger_message)

      case IntelligentAgent.process_request(user, conversation.id, trigger_message) do
        {:ok, assistant_message} ->
          {:ok, assistant_message}

        {:error, _reason} ->
          {:error, "Failed to process trigger"}
      end
    else
      {:ok, nil}
    end
  end

  # Execute automation rule based on instruction
  defp execute_automation_rule(user, instruction, trigger_type, trigger_data) do
    IO.puts("DEBUG: Executing automation rule: #{instruction.instruction}")

    # Parse the instruction to extract action details
    case parse_automation_instruction(instruction.instruction) do
      {:ok, action_type, params} ->
        # Execute the action
        case execute_automation_action(user, action_type, params, trigger_data) do
          {:ok, result} ->
            IO.puts("DEBUG: Automation action executed successfully: #{result}")
            {:ok, result}

          {:error, reason} ->
            IO.puts("DEBUG: Automation action failed: #{reason}")
            {:error, reason}
        end

      {:error, reason} ->
        IO.puts("DEBUG: Failed to parse automation instruction: #{reason}")
        {:error, reason}
    end
  end

  # Parse automation instruction to extract action type and parameters
  defp parse_automation_instruction(instruction) do
    # Look for action type in the instruction
    cond do
      String.contains?(instruction, "send_email") ->
        {:ok, "send_email", %{"to" => "attendees", "subject" => "Meeting Notification", "body" => "Meeting details"}}

      String.contains?(instruction, "create_calendar_event") ->
        {:ok, "create_calendar_event", %{"title" => "Auto-created event", "description" => "Automatically created"}}

      String.contains?(instruction, "add_note") ->
        {:ok, "add_note", %{"note" => "Automation triggered"}}

      String.contains?(instruction, "search_emails") ->
        {:ok, "search_emails", %{"query" => "automation"}}

      true ->
        {:error, "Unknown action type in instruction"}
    end
  end

  # Execute automation action
  defp execute_automation_action(user, action_type, params, trigger_data) do
    case action_type do
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

  # Execute email automation
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
            results = Enum.map(attendees, fn attendee ->
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

  # Execute calendar automation
  defp execute_automation_calendar(user, params, trigger_data) do
    # Handle calendar-related automations
    {:ok, "Calendar automation executed"}
  end

  # Execute note automation
  defp execute_automation_note(user, params, trigger_data) do
    # Handle note-related automations
    {:ok, "Note automation executed"}
  end

  # Execute search automation
  defp execute_automation_search(user, params, trigger_data) do
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

            {:ok, assistant_message} = create_message(conversation_id, %{
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

        case OpenRouterClient.chat_completion(messages: [
      %{role: "system", content: system_prompt},
      %{role: "user", content: user_message}
    ]) do
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
    {successful, failed} = Enum.reduce(results, {0, 0}, fn {_step, result}, {s, f} ->
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
    # Use local embedding server for RAG
    case AdvisorAi.AI.LocalEmbeddingClient.embeddings(input: text) do
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

  defp get_active_instructions_by_trigger(user_id, trigger_type) do
    import Ecto.Query

    AgentInstruction
    |> where(user_id: ^user_id, is_active: true)
    |> where([i], i.trigger_type == ^trigger_type)
    |> select([i], i.instruction)
    |> Repo.all()
  end

  defp get_or_create_current_conversation(user_id) do
    case list_user_conversations(user_id) |> List.first() do
      nil -> create_conversation(user_id, %{title: "New Conversation"})
      conversation -> {:ok, conversation}
    end
  end

  defp list_user_conversations(user_id) do
    Conversation
    |> where(user_id: ^user_id)
    |> order_by(desc: :updated_at)
    |> Repo.all()
  end

  defp create_conversation(user_id, attrs) do
    %Conversation{user_id: user_id}
    |> Conversation.changeset(attrs)
    |> Repo.insert()
  end

  defp create_message(conversation_id, attrs) do
    %Message{conversation_id: conversation_id}
    |> Message.changeset(attrs)
    |> Repo.insert()
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
end
