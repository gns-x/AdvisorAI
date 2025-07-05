defmodule AdvisorAi.AI.Agent do
  @moduledoc """
  Main AI agent service that handles:
  - RAG (Retrieval Augmented Generation) using vector embeddings
  - Tool calling for actions like email, calendar, and HubSpot operations
  - Task management and memory for ongoing operations
  - Proactive agent behavior based on triggers
  """

  import Ecto.Query
  alias AdvisorAi.Repo
  alias AdvisorAi.Chat.{Conversation, Message}
  alias AdvisorAi.AI.{VectorEmbedding, AgentInstruction, OllamaClient}
  alias AdvisorAi.Tasks.AgentTask
  alias AdvisorAi.Integrations.{Gmail, Calendar, HubSpot}

  # OpenAI client will be configured at runtime

  def process_user_message(user, conversation_id, message_content) do
    # Get conversation context
    conversation = get_conversation_with_context(conversation_id, user.id)

    # Create user message
    {:ok, _user_message} = create_message(conversation_id, %{
      role: "user",
      content: message_content
    })

    # Get relevant context from RAG
    context = get_relevant_context(user.id, message_content)

    # Get active instructions
    instructions = get_active_instructions(user.id)

    # Process with AI agent
    case process_with_ai_agent(user, conversation, message_content, context, instructions) do
      {:ok, response, tool_calls} ->
        # Create assistant message
        {:ok, assistant_message} = create_message(conversation_id, %{
          role: "assistant",
          content: response,
          tool_calls: nil
        })

        # Tool calls disabled for now

        {:ok, assistant_message}

      {:error, reason} ->
        # Create error message
        {:ok, error_message} = create_message(conversation_id, %{
          role: "assistant",
          content: "I apologize, but I encountered an error: #{reason}"
        })
        {:ok, error_message}
    end
  end

  def handle_trigger(user, trigger_type, trigger_data) do
    # Get active instructions for this trigger
    instructions = get_active_instructions_by_trigger(user.id, trigger_type)

    if length(instructions) > 0 do
      # Create a system message with the trigger context
      trigger_message = build_trigger_message(trigger_type, trigger_data)

      # Get conversation context
      {:ok, conversation} = get_or_create_current_conversation(user.id)

      # Process with AI agent
      context = get_relevant_context(user.id, trigger_message)

      case process_with_ai_agent(user, conversation, trigger_message, context, instructions) do
        {:ok, response, tool_calls} ->
          # Create assistant message
          {:ok, assistant_message} = create_message(conversation.id, %{
            role: "assistant",
            content: response,
            tool_calls: nil
          })

          # Tool calls disabled for now

          {:ok, assistant_message}

        {:error, _reason} ->
          {:error, "Failed to process trigger"}
      end
    else
      {:ok, nil}
    end
  end

  defp process_with_ai_agent(user, conversation, message, context, instructions) do
    # Check if Ollama is running
    case OllamaClient.health_check() do
      {:ok, _status} ->
      # Build system prompt
      system_prompt = build_system_prompt(user, context, instructions)

      # Build messages for OpenAI
      messages = [
        %{role: "system", content: system_prompt},
        %{role: "user", content: message}
      ]

      # Add conversation history (last 10 messages)
      conversation_history = get_conversation_history(conversation.id, 10)
      messages = messages ++ conversation_history

      # Call Ollama
      IO.inspect("About to call Ollama...")
      case OllamaClient.chat_completion(
        model: "llama3.2:3b",
        messages: messages,
        temperature: 0.7
      ) do
        {:ok, %{choices: [%{message: assistant_message}]}} ->
          response = assistant_message.content || ""
          {:ok, response, []}

              {:error, _reason} ->
        IO.inspect(_reason, label: "Ollama API Error Details")
        {:error, "Ollama API error: #{inspect(_reason)}"}
      end

      {:error, reason} ->
        {:error, "Ollama is not running. Please start Ollama with: brew services start ollama"}
    end
  end

  defp build_system_prompt(user, context, instructions) do
    """
    You are an AI assistant for #{user.name}, a financial advisor. You have access to their Gmail, Google Calendar, and HubSpot CRM.

    ## Your Capabilities:
    - Answer questions about clients using information from emails and HubSpot
    - Schedule appointments and manage calendar events
    - Send emails to clients
    - Create and update HubSpot contacts and notes
    - Handle ongoing tasks and follow-ups

    ## Current Context:
    #{context}

    ## Active Instructions:
    #{Enum.map_join(instructions, "\n", &"- #{&1.instruction}")}

    ## Guidelines:
    - Be professional and helpful
    - Use available tools to take actions when requested
    - Remember ongoing tasks and follow up appropriately
    - Be proactive when you see opportunities to help
    - Always maintain client confidentiality
    """
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

  defp define_available_tools do
    [
      %{
        type: "function",
        function: %{
          name: "search_emails",
          description: "Search through user's emails for specific information",
          parameters: %{
            type: "object",
            properties: %{
              query: %{
                type: "string",
                description: "Search query for emails"
              }
            },
            required: ["query"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "search_hubspot_contacts",
          description: "Search for contacts in HubSpot CRM",
          parameters: %{
            type: "object",
            properties: %{
              query: %{
                type: "string",
                description: "Search query for contacts"
              }
            },
            required: ["query"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "send_email",
          description: "Send an email to a recipient",
          parameters: %{
            type: "object",
            properties: %{
              to: %{
                type: "string",
                description: "Email address of recipient"
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
        }
      },
      %{
        type: "function",
        function: %{
          name: "schedule_appointment",
          description: "Schedule an appointment in Google Calendar",
          parameters: %{
            type: "object",
            properties: %{
              title: %{
                type: "string",
                description: "Appointment title"
              },
              start_time: %{
                type: "string",
                description: "Start time in ISO format"
              },
              end_time: %{
                type: "string",
                description: "End time in ISO format"
              },
              attendees: %{
                type: "array",
                items: %{type: "string"},
                description: "List of attendee email addresses"
              },
              description: %{
                type: "string",
                description: "Appointment description"
              }
            },
            required: ["title", "start_time", "end_time"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "create_hubspot_contact",
          description: "Create a new contact in HubSpot",
          parameters: %{
            type: "object",
            properties: %{
              email: %{
                type: "string",
                description: "Contact email address"
              },
              first_name: %{
                type: "string",
                description: "Contact first name"
              },
              last_name: %{
                type: "string",
                description: "Contact last name"
              },
              company: %{
                type: "string",
                description: "Contact company"
              },
              notes: %{
                type: "string",
                description: "Additional notes about the contact"
              }
            },
            required: ["email"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "add_hubspot_note",
          description: "Add a note to a HubSpot contact",
          parameters: %{
            type: "object",
            properties: %{
              contact_email: %{
                type: "string",
                description: "Email of the contact"
              },
              note: %{
                type: "string",
                description: "Note content"
              }
            },
            required: ["contact_email", "note"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "create_task",
          description: "Create a task for later execution",
          parameters: %{
            type: "object",
            properties: %{
              description: %{
                type: "string",
                description: "Task description"
              },
              scheduled_at: %{
                type: "string",
                description: "When to execute the task (ISO format)"
              },
              context: %{
                type: "object",
                description: "Additional context for the task"
              }
            },
            required: ["description"]
          }
        }
      }
    ]
  end

  defp execute_tool_calls(user, conversation_id, tool_calls) do
    Enum.each(tool_calls, fn tool_call ->
      case tool_call.function.name do
        "search_emails" ->
          args = Jason.decode!(tool_call.function.arguments)
          _result = Gmail.search_emails(user, args["query"])
          # Store result for next iteration

        "search_hubspot_contacts" ->
          args = Jason.decode!(tool_call.function.arguments)
          _result = HubSpot.search_contacts(user, args["query"])
          # Store result for next iteration

        "send_email" ->
          args = Jason.decode!(tool_call.function.arguments)
          Gmail.send_email(user, args["to"], args["subject"], args["body"])

        "schedule_appointment" ->
          args = Jason.decode!(tool_call.function.arguments)
          Calendar.create_event(user, args)

        "create_hubspot_contact" ->
          args = Jason.decode!(tool_call.function.arguments)
          HubSpot.create_contact(user, args)

        "add_hubspot_note" ->
          args = Jason.decode!(tool_call.function.arguments)
          HubSpot.add_note(user, args["contact_email"], args["note"])

        "create_task" ->
          args = Jason.decode!(tool_call.function.arguments)
          create_agent_task(user, conversation_id, args)
      end
    end)
  end

  defp get_relevant_context(_user_id, _query) do
    # Temporarily disabled vector search to fix the error
    ""
  end

  defp get_embedding(_text) do
    # Temporarily disabled embeddings to fix the error
    {:error, "embeddings disabled"}
  end

  defp search_similar_content(_user_id, _query_embedding, _limit) do
    # Temporarily disabled vector search to fix the error
    []
  end

  defp get_active_instructions(user_id) do
    AgentInstruction
    |> where(user_id: ^user_id, is_active: true)
    |> Repo.all()
  end

  defp get_active_instructions_by_trigger(user_id, trigger_type) do
    AgentInstruction
    |> where(user_id: ^user_id, is_active: true, trigger_type: ^trigger_type)
    |> Repo.all()
  end

  defp get_conversation_with_context(conversation_id, user_id) do
    Conversation
    |> where(id: ^conversation_id, user_id: ^user_id)
    |> preload(messages: ^from(m in Message, order_by: m.inserted_at))
    |> Repo.one!()
  end

  defp get_conversation_history(conversation_id, limit) do
    Message
    |> where(conversation_id: ^conversation_id)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> order_by(:inserted_at)
    |> select([m], %{role: m.role, content: m.content})
    |> Repo.all()
  end

  defp create_message(conversation_id, attrs) do
    %Message{conversation_id: conversation_id}
    |> Message.changeset(attrs)
    |> Repo.insert()
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

  defp create_agent_task(user, conversation_id, attrs) do
    %AgentTask{
      user_id: user.id,
      conversation_id: conversation_id,
      type: "scheduled",
      status: "pending",
      description: attrs["description"],
      context: attrs["context"] || %{},
      scheduled_at: parse_datetime(attrs["scheduled_at"])
    }
    |> AgentTask.changeset(%{})
    |> Repo.insert()
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end
end
