defmodule AdvisorAi.AI.IntelligentAgent do
  @moduledoc """
  AI-powered intelligent agent that uses real AI models to understand and execute complex tasks.
  """

  alias AdvisorAi.{Accounts, Chat, AI}
  alias AdvisorAi.Integrations.{Gmail, Calendar, HubSpot, GoogleContacts, GoogleAuth}
  alias AI.{OpenRouterClient, TogetherClient, OllamaClient, VectorEmbedding, AgentInstruction}

  @doc """
  Process a user request using AI to understand and execute tasks intelligently.
  """
  def process_request(user, conversation_id, user_message) do
    conversation = get_conversation_with_context(conversation_id, user.id)
    user_context = get_comprehensive_user_context(user)
    context = build_ai_context(user, conversation, user_context)
    prompt = build_hybrid_prompt(user_message, context)

    case get_ai_response(prompt) do
      {:ok, ai_response} ->
        handle_hybrid_ai_response(user, conversation_id, ai_response, context)
      {:error, _reason} ->
        create_agent_response(user, conversation_id, "I'm having trouble processing your request right now. Please try again.", "error")
    end
  end

  # Build a prompt that instructs the LLM to return either a conversational response or a structured plan for real data
  defp build_hybrid_prompt(user_message, context) do
    """
    You are an advanced AI assistant with access to Gmail, Google Calendar, and Google Contacts APIs. The user will ask you to perform any task. If the request requires real data (like listing contacts, emails, or events), return a JSON object with the action and parameters, e.g. {"action": "get_contacts", "params": {}}. If the request is conversational or does not require real data, return a conversational response or a JSON object with a 'response' key. Never ask for confirmation, never list available actions, and never require the user to use specific keywords. Always act autonomously and return only the final result or the action to perform.

    User Request: \"#{user_message}\"

    User Context:
    - Name: #{context.user.name}
    - Email: #{context.user.email}
    - Google Connected: #{context.user.google_connected}
    - Gmail Available: #{context.user.gmail_available}
    - Calendar Available: #{context.user.calendar_available}

    Current Time: #{context.current_time}

    Recent Conversation:
    #{context.conversation}

    Instructions:
    1. If the user request requires accessing real data (contacts, emails, calendar, etc.), return a JSON object with the action and parameters, e.g. {"action": "get_contacts", "params": {}}.
    2. If the request is conversational or informational, return a conversational response or a JSON object with a 'response' key.
    3. Never output a plan or a list of possible actions. Only output the final answer or the action to perform.
    4. Never require the user to use specific words or phrases. Be proactive and intelligent.
    5. If you are unsure, make your best guess and act.
    6. Never output anything except the final answer or a single JSON object.
    """
  end

  # Handle the AI response: if it's a JSON action, execute it generically; otherwise, display the response
  defp handle_hybrid_ai_response(user, conversation_id, ai_response, context) do
    case parse_hybrid_ai_response(ai_response) do
      {:action, action, params} ->
        execute_generic_action(user, conversation_id, action, params, context)
      {:response, response} ->
        create_agent_response(user, conversation_id, response, "conversation")
      :raw ->
        create_agent_response(user, conversation_id, ai_response, "conversation")
    end
  end

  # Parse the AI response: detect action or response
  defp parse_hybrid_ai_response(response) do
    case Regex.run(~r/\{.*\}/s, response) do
      [json_str] ->
        try do
          case Jason.decode(json_str) do
            {:ok, %{"action" => action} = map} -> {:action, action, Map.get(map, "params", %{})}
            {:ok, %{"response" => resp}} -> {:response, resp}
            _ -> :raw
          end
        rescue
          _ -> :raw
        end
      _ -> :raw
    end
  end

  # Generic executor for any supported action
  defp execute_generic_action(user, conversation_id, action, params, context) do
    case {String.downcase(action), params} do
      {"get_contacts", _} ->
        case GoogleContacts.get_all_contacts(user, page_size: params["page_size"] || 50) do
          {:ok, contacts} ->
            if length(contacts) > 0 do
              contact_list = Enum.take(contacts, 20)
              |> Enum.map(fn contact ->
                name = case contact.names do
                  [name | _] -> name.display_name
                  _ -> "Unknown"
                end
                email = case contact.email_addresses do
                  [email | _] -> email.value
                  _ -> "No email"
                end
                phone = case contact.phone_numbers do
                  [phone | _] -> phone.value
                  _ -> "No phone"
                end
                "• #{name} (#{email}, #{phone})"
              end)
              |> Enum.join("\n")
              response = "Your contacts (#{length(contacts)} total):\n\n#{contact_list}"
              if length(contacts) > 20 do
                response = response <> "\n\n... and #{length(contacts) - 20} more contacts"
              end
              create_agent_response(user, conversation_id, response, "action")
            else
              create_agent_response(user, conversation_id, "No contacts found.", "action")
            end
          {:error, reason} -> create_agent_response(user, conversation_id, "Failed to get contacts: #{reason}", "error")
        end
      {"search_emails", _} ->
        query = params["query"] || params["q"] || ""
        case Gmail.search_emails(user, query) do
          {:ok, emails} ->
            if length(emails) > 0 do
              email_list = Enum.map_join(emails, "\n", fn email -> "- #{email.subject} (from: #{email.from})" end)
              create_agent_response(user, conversation_id, "Search results:\n#{email_list}", "action")
            else
              create_agent_response(user, conversation_id, "No emails found matching the search criteria.", "action")
            end
          {:error, reason} -> create_agent_response(user, conversation_id, "Failed to search emails: #{reason}", "error")
        end
      {"get_recent_emails", _} ->
        max_results = params["max_results"] || 10
        case Gmail.get_recent_emails(user, max_results) do
          {:ok, emails} ->
            if length(emails) > 0 do
              email_summary = Enum.take(emails, 5)
              |> Enum.map(fn email -> "• #{email.subject} (from: #{email.from})" end)
              |> Enum.join("\n")
              response = "Here are your recent emails:\n\n#{email_summary}"
              if length(emails) > 5 do
                response = response <> "\n\n... and #{length(emails) - 5} more emails"
              end
              create_agent_response(user, conversation_id, response, "action")
            else
              create_agent_response(user, conversation_id, "No recent emails found.", "action")
            end
          {:error, reason} -> create_agent_response(user, conversation_id, "I couldn't retrieve your recent emails: #{reason}", "error")
        end
      {"create_calendar_event", _} ->
        case Calendar.create_event(user, params) do
          {:ok, event} -> create_agent_response(user, conversation_id, "Calendar event created successfully: #{event}", "action")
          {:error, reason} -> create_agent_response(user, conversation_id, "Failed to create calendar event: #{reason}", "error")
        end
      {"get_calendar_events", _} ->
        case Calendar.get_events(user, params["time_min"], params["time_max"]) do
          {:ok, events} ->
            if length(events) > 0 do
              event_list = Enum.map_join(events, "\n", fn event -> "- #{event.summary} (#{event.start_time})" end)
              create_agent_response(user, conversation_id, "Calendar events:\n#{event_list}", "action")
            else
              create_agent_response(user, conversation_id, "No calendar events found for the specified criteria.", "action")
            end
          {:error, reason} -> create_agent_response(user, conversation_id, "Failed to get calendar events: #{reason}", "error")
        end
      # Add more generic cases here as needed for other APIs
      {other, _} ->
        create_agent_response(user, conversation_id, "Action '#{other}' is not supported yet.", "error")
    end
  end

  # Build a universal prompt for the LLM to decide and act
  defp build_universal_prompt(user_message, context) do
    """
    You are an advanced AI assistant with access to Gmail, Google Calendar, and Google Contacts APIs. The user will ask you to perform any task, and you must decide what to do and execute it. Do not ask for confirmation, do not list available actions, and do not require the user to use specific keywords. Always act autonomously and return only the final result.

    User Request: \"#{user_message}\"

    User Context:
    - Name: #{context.user.name}
    - Email: #{context.user.email}
    - Google Connected: #{context.user.google_connected}
    - Gmail Available: #{context.user.gmail_available}
    - Calendar Available: #{context.user.calendar_available}

    Current Time: #{context.current_time}

    Recent Conversation:
    #{context.conversation}

    Instructions:
    1. Intelligently interpret the user's request and decide what to do, without relying on specific keywords or imperative forms.
    2. If the request requires accessing Gmail, Calendar, or Contacts, use the appropriate API and return the result.
    3. If the request is informational or conversational, respond directly.
    4. Always return only the final result or answer, never a list of possible actions or a request for confirmation.
    5. If you need to perform an action, return a JSON object with the action and parameters, e.g.:
    {"action": "send_email", "params": {"to": "example@email.com", "subject": "Subject", "body": "Body"}}
    6. If the request is conversational, return a JSON object with {"response": "..."}
    7. Never require the user to use specific words or phrases. Be proactive and intelligent.
    8. If you are unsure, make your best guess and act.
    9. Never output anything except the JSON object or the final answer.
    """
  end

  # Build comprehensive context for AI
  def build_ai_context(user, conversation, user_context) do
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
      available_actions: [
        # Gmail API functions
        "search_emails", "get_emails", "send_email", "compose_draft", "get_recent_emails", "list_emails",
        # Calendar API functions
        "create_calendar_event", "get_calendar_events", "update_calendar_event", "delete_calendar_event",
        # Contact API functions
        "find_contact", "list_contacts", "create_contact", "update_contact", "delete_contact"
      ],
      current_time: DateTime.utc_now()
    }
  end

  # Get AI response using available AI clients
  defp get_ai_response(prompt) do
    # Try OpenRouter first (most powerful)
    case try_openrouter(prompt) do
      {:ok, response} -> {:ok, response}
      {:error, _} ->
        # Fallback to Together AI
        case try_together_ai(prompt) do
          {:ok, response} -> {:ok, response}
          {:error, _} ->
            # Fallback to Ollama
            try_ollama(prompt)
        end
    end
  end

  defp try_openrouter(prompt) do
    messages = [
      %{"role" => "system", "content" => "You are a helpful AI assistant."},
      %{"role" => "user", "content" => prompt}
    ]

    case OpenRouterClient.chat_completion(messages: messages, temperature: 0.3) do
      {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
        {:ok, content}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp try_together_ai(prompt) do
    messages = [
      %{"role" => "system", "content" => "You are a helpful AI assistant."},
      %{"role" => "user", "content" => prompt}
    ]

    case TogetherClient.chat_completion(messages: messages, temperature: 0.3) do
      {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
        {:ok, content}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp try_ollama(prompt) do
    messages = [
      %{"role" => "system", "content" => "You are a helpful AI assistant."},
      %{"role" => "user", "content" => prompt}
    ]

    case OllamaClient.chat_completion(messages: messages, temperature: 0.3) do
      {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
        {:ok, content}
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Helper functions
  defp has_valid_google_tokens?(user) do
    case AdvisorAi.Accounts.get_user_google_account(user.id) do
      nil -> false
      account ->
        account.access_token != nil and account.refresh_token != nil
    end
  end

  defp has_gmail_access?(user) do
    case AdvisorAi.Accounts.get_user_google_account(user.id) do
      nil -> false
      account ->
        account.access_token != nil and account.refresh_token != nil and
        Enum.any?(account.scopes || [], fn s -> String.contains?(s, "gmail") end)
    end
  end

  defp has_calendar_access?(user) do
    case AdvisorAi.Accounts.get_user_google_account(user.id) do
      nil -> false
      account ->
        account.access_token != nil and account.refresh_token != nil and
        Enum.any?(account.scopes || [], fn s -> String.contains?(s, "calendar") end)
    end
  end

  defp get_conversation_with_context(conversation_id, user_id) do
    Chat.get_conversation!(conversation_id, user_id)
  end

  defp get_comprehensive_user_context(user) do
    %{
      user_info: %{
        name: user.name,
        email: user.email,
        google_connected: has_valid_google_tokens?(user)
      },
      recent_conversations: get_recent_conversations(user.id)
    }
  end

  defp get_conversation_summary(conversation) do
    "Conversation started at #{conversation.inserted_at}"
  end

  defp get_recent_messages(conversation) do
    # Get recent messages from conversation
    []
  end

  defp get_recent_conversations(user_id) do
    Chat.list_user_conversations(user_id)
  end

  defp create_agent_response(user, conversation_id, response_content, response_type) do
    # Create the agent's response message
    case Chat.create_message(conversation_id, %{
      user_id: user.id,
      role: "assistant",
      content: response_content,
      metadata: %{response_type: response_type}
    }) do
      {:ok, message} -> {:ok, message}
      {:error, changeset} -> {:error, changeset}
    end
  end

  # Calendar API functions
  defp execute_get_calendar_events_action(user, _conversation_id, params, _context) do
    case Calendar.get_events(user, params["time_min"], params["time_max"]) do
      {:ok, events} ->
        if length(events) > 0 do
          event_list = Enum.map_join(events, "\n", fn event ->
            "- #{event.summary} (#{event.start_time})"
          end)
          {:ok, "Calendar events:\n#{event_list}"}
        else
          {:ok, "No calendar events found for the specified criteria."}
        end
      {:error, reason} -> {:error, "Failed to get calendar events: #{reason}"}
    end
  end

  defp execute_update_calendar_event_action(user, _conversation_id, params, _context) do
    case Calendar.update_event(user, params["event_id"], params) do
      {:ok, event} -> {:ok, "Calendar event updated successfully: #{event}"}
      {:error, reason} -> {:error, "Failed to update calendar event: #{reason}"}
    end
  end

  defp execute_delete_calendar_event_action(user, _conversation_id, params, _context) do
    case Calendar.delete_event(user, params["event_id"]) do
      {:ok, _} -> {:ok, "Calendar event deleted successfully."}
      {:error, reason} -> {:error, "Failed to delete calendar event: #{reason}"}
    end
  end

  # Contact API functions
  defp execute_find_contact_action(user, _conversation_id, params, _context) do
    query = params["email"] || params["name"] || params[:email] || params[:name]
    if is_nil(query) or query == "" do
      {:ok, nil} # Gracefully skip if no query provided
    else
      case GoogleContacts.find_contact(user, params) do
        {:ok, contact} ->
          contact_name = get_in(contact, ["names", Access.at(0), "displayName"]) || "Unknown"
          contact_email = get_in(contact, ["emailAddresses", Access.at(0), "value"]) || "No email"
          {:ok, "Found contact: #{contact_name} (#{contact_email})"}
        {:ok, nil} ->
          {:ok, "No contact found matching the criteria."}
        {:error, reason} ->
          {:error, "Failed to find contact: #{reason}"}
      end
    end
  end

  defp execute_create_contact_action(user, _conversation_id, params, _context) do
    case GoogleContacts.create_contact(user, params) do
      {:ok, contact} ->
        contact_name = get_in(contact, ["names", Access.at(0), "displayName"]) || "Unknown"
        {:ok, "Contact created successfully: #{contact_name}"}
      {:error, reason} -> {:error, "Failed to create contact: #{reason}"}
    end
  end

  defp execute_update_contact_action(user, _conversation_id, params, _context) do
    case GoogleContacts.update_contact(user, params["contact_id"], params) do
      {:ok, contact} ->
        contact_name = get_in(contact, ["names", Access.at(0), "displayName"]) || "Unknown"
        {:ok, "Contact updated successfully: #{contact_name}"}
      {:error, reason} -> {:error, "Failed to update contact: #{reason}"}
    end
  end

  defp execute_delete_contact_action(user, _conversation_id, params, _context) do
    case GoogleContacts.delete_contact(user, params["contact_id"]) do
      {:ok, _} -> {:ok, "Contact deleted successfully."}
      {:error, reason} -> {:error, "Failed to delete contact: #{reason}"}
    end
  end

  # Gmail API functions (update existing ones to match new naming)
  defp execute_search_emails_action(user, _conversation_id, params, _context) do
    query = params["query"] || params["q"]
    case Gmail.search_emails(user, query) do
      {:ok, emails} ->
        if length(emails) > 0 do
          email_list = Enum.map_join(emails, "\n", fn email ->
            "- #{email.subject} (from: #{email.from})"
          end)
          {:ok, "Search results:\n#{email_list}"}
        else
          {:ok, "No emails found matching the search criteria."}
        end
      {:error, reason} -> {:error, "Failed to search emails: #{reason}"}
    end
  end
end
