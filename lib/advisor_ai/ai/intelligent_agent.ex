defmodule AdvisorAi.AI.IntelligentAgent do
  @moduledoc """
  AI-powered intelligent agent that uses real AI models to understand and execute complex tasks.
  """

  alias AdvisorAi.{Accounts, Chat, AI}
  alias AdvisorAi.Integrations.{Gmail, Calendar, HubSpot, GoogleContacts, GoogleAuth}
  alias AI.{OpenRouterClient, TogetherClient, OllamaClient, VectorEmbedding, AgentInstruction}

  @imperative_verbs ["send", "add", "schedule", "create", "email", "invite", "write", "compose", "when", "automate"]

  @doc """
  Process a user request using AI to understand and execute tasks intelligently.
  """
  def process_request(user, conversation_id, user_message) do
    conversation = get_conversation_with_context(conversation_id, user.id)
    user_context = get_comprehensive_user_context(user)
    imperative = imperative_prompt?(user_message)
    automation_request = automation_request?(user_message)

    # Debug logging
    IO.puts("DEBUG: Message: #{user_message}")
    IO.puts("DEBUG: Imperative: #{imperative}")
    IO.puts("DEBUG: Automation: #{automation_request}")

    cond do
      automation_request ->
        # Handle automation setup
        handle_automation_request(user, conversation_id, user_message, conversation, user_context)

      imperative ->
        # Use AI to understand and execute the task
        execute_ai_powered_task(user, conversation_id, user_message, conversation, user_context)

      true ->
        # Use AI for general conversation
        handle_general_conversation(user, conversation_id, user_message, conversation, user_context)
    end
  end

  defp imperative_prompt?(message) do
    message_down = String.downcase(String.trim(message))
    Enum.any?(@imperative_verbs, fn verb -> String.starts_with?(message_down, verb) end)
  end

  defp automation_request?(message) do
    message_down = String.downcase(String.trim(message))
    automation_keywords = ["when", "automatically", "every time", "always", "trigger", "automation", "rule"]
    Enum.any?(automation_keywords, fn keyword -> String.contains?(message_down, keyword) end)
  end

  # Use AI to understand and execute tasks
  defp execute_ai_powered_task(user, conversation_id, user_message, conversation, user_context) do
    # Build context for AI
    context = build_ai_context(user, conversation, user_context)

    # Create AI prompt for task understanding and execution
    prompt = build_task_execution_prompt(user_message, context)

    IO.puts("DEBUG: AI Prompt: #{prompt}")

    # Get AI response
    case get_ai_response(prompt) do
      {:ok, ai_response} ->
        IO.puts("DEBUG: AI Response: #{ai_response}")
        # Parse AI response and execute actions
        execute_ai_instructions(user, conversation_id, ai_response, user_message, context)

      {:error, reason} ->
        # Fallback to basic execution
        IO.puts("AI Error: #{reason}")
        execute_fallback_task(user, conversation_id, user_message, context)
    end
  end

    # Handle general conversation with AI
  defp handle_general_conversation(user, conversation_id, user_message, conversation, user_context) do
    context = build_ai_context(user, conversation, user_context)

    IO.puts("DEBUG: General conversation handler:")
    IO.puts("  - Gmail available: #{context.user.gmail_available}")
    IO.puts("  - Calendar available: #{context.user.calendar_available}")

    # Check if this is a request for specific Gmail/Calendar data
    is_data = is_data_request?(user_message)
    has_access = context.user.gmail_available or context.user.calendar_available

    IO.puts("  - Is data request: #{is_data}")
    IO.puts("  - Has access: #{has_access}")

    if is_data and has_access do
      IO.puts("DEBUG: Handling as task request")
      # Handle as a task request
      execute_ai_powered_task(user, conversation_id, user_message, conversation, user_context)
    else
      IO.puts("DEBUG: Handling as general conversation")
      # Handle as general conversation
      prompt = build_conversation_prompt(user_message, context)

      case get_ai_response(prompt) do
        {:ok, ai_response} ->
          create_agent_response(user, conversation_id, ai_response, "conversation")

        {:error, reason} ->
          create_agent_response(user, conversation_id, "I'm having trouble processing your request right now. Please try again.", "error")
      end
    end
  end

    # Check if the message is requesting specific data from Gmail/Calendar
  defp is_data_request?(message) do
    message_down = String.downcase(message)

    # Gmail data requests - more comprehensive keywords
    gmail_keywords = ["email", "emails", "gmail", "inbox", "search", "find", "list", "show", "get", "recent", "last", "sent", "received"]
    gmail_indicators = ["contain", "with", "from", "to", "subject", "bcg", "meeting", "urgent", "word", "about", "regarding"]

    # Calendar data requests
    calendar_keywords = ["calendar", "event", "events", "meeting", "schedule", "appointment"]
    calendar_indicators = ["today", "tomorrow", "this week", "next week", "when", "time", "date"]

    has_gmail_keyword = Enum.any?(gmail_keywords, fn keyword -> String.contains?(message_down, keyword) end)
    has_gmail_indicator = Enum.any?(gmail_indicators, fn indicator -> String.contains?(message_down, indicator) end)

    has_calendar_keyword = Enum.any?(calendar_keywords, fn keyword -> String.contains?(message_down, keyword) end)
    has_calendar_indicator = Enum.any?(calendar_indicators, fn indicator -> String.contains?(message_down, indicator) end)

    # More flexible logic: if it has Gmail keywords, it's likely a data request
    # Only require indicators for very specific searches
    is_specific_search = has_gmail_indicator or has_calendar_indicator
    has_gmail_request = has_gmail_keyword and (is_specific_search or String.contains?(message_down, "recent") or String.contains?(message_down, "last") or String.contains?(message_down, "sent"))
    has_calendar_request = has_calendar_keyword and (has_calendar_indicator or String.contains?(message_down, "today") or String.contains?(message_down, "tomorrow"))

    result = has_gmail_request or has_calendar_request

    IO.puts("DEBUG: Data request check for '#{message}':")
    IO.puts("  - Has Gmail keyword: #{has_gmail_keyword}")
    IO.puts("  - Has Gmail indicator: #{has_gmail_indicator}")
    IO.puts("  - Has Calendar keyword: #{has_calendar_keyword}")
    IO.puts("  - Has Calendar indicator: #{has_calendar_indicator}")
    IO.puts("  - Is specific search: #{is_specific_search}")
    IO.puts("  - Has Gmail request: #{has_gmail_request}")
    IO.puts("  - Has Calendar request: #{has_calendar_request}")
    IO.puts("  - Is data request: #{result}")

    result
  end

  # Handle automation setup requests
  defp handle_automation_request(user, conversation_id, user_message, conversation, user_context) do
    context = build_ai_context(user, conversation, user_context)
    prompt = build_automation_prompt(user_message, context)

    IO.puts("DEBUG: Automation Prompt: #{prompt}")

    case get_ai_response(prompt) do
      {:ok, ai_response} ->
        IO.puts("DEBUG: Automation AI Response: #{ai_response}")
        parse_and_setup_automation(user, conversation_id, ai_response, user_message, context)

      {:error, reason} ->
        IO.puts("Automation AI Error: #{reason}")
        create_agent_response(user, conversation_id, "I'm having trouble setting up that automation. Please try rephrasing your request.", "error")
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
      available_actions: [
        "send_email",
        "create_calendar_event",
        "find_contact",
        "search_emails",
        "compose_draft",
        "get_emails",
        "list_emails",
        "get_recent_emails"
      ],
      current_time: DateTime.utc_now()
    }
  end

  # Build AI prompt for task execution
  defp build_task_execution_prompt(user_message, context) do
    """
    You are an intelligent AI assistant with access to Gmail and Google Calendar.
    The user wants you to execute a task: "#{user_message}"

    User Context:
    - Name: #{context.user.name}
    - Email: #{context.user.email}
    - Google Connected: #{context.user.google_connected}
    - Gmail Available: #{context.user.gmail_available}
    - Calendar Available: #{context.user.calendar_available}

    Available Actions: #{Enum.join(context.available_actions, ", ")}
    Current Time: #{context.current_time}

    Recent Conversation:
    #{context.conversation}

    CRITICAL: You MUST respond with valid JSON only. No other text before or after the JSON.

    Instructions:
    1. Analyze the user's request carefully
    2. Extract all necessary information (emails, names, times, subjects, etc.)
    3. Determine what actions need to be performed
            4. Provide ONLY a JSON response with the following structure:
    {
      "actions": [
        {
          "type": "send_email|create_calendar_event|find_contact|search_emails|compose_draft|get_emails|list_emails|get_recent_emails",
          "params": {
            // Action-specific parameters
          }
        }
      ],
      "summary": "Brief summary of what you're doing",
      "response": "User-friendly response explaining what you did"
    }

    Examples:
    - For "Show me my recent emails": {"actions": [{"type": "get_recent_emails", "params": {"max_results": 10}}], "summary": "Getting recent emails", "response": "I'll retrieve your recent emails for you."}
    - For "Find emails from John": {"actions": [{"type": "search_emails", "params": {"query": "from:John"}}], "summary": "Searching emails from John", "response": "I'll search for emails from John."}
    - For "Send email to john@example.com about meeting": {"actions": [{"type": "send_email", "params": {"to": "john@example.com", "subject": "Meeting", "body": "Hello, I'd like to discuss our meeting."}}], "summary": "Sending email about meeting", "response": "I'll send an email to john@example.com about the meeting."}

    If you need to send an email, extract the recipient email, subject, and create appropriate content.
    If you need to create a calendar event, extract the time, attendees, and description.
    Be intelligent and contextual in your responses.
    """
  end

  # Build AI prompt for general conversation
  defp build_conversation_prompt(user_message, context) do
    """
    You are an intelligent AI assistant with access to Gmail and Google Calendar.
    The user said: "#{user_message}"

    User Context:
    - Name: #{context.user.name}
    - Email: #{context.user.email}
    - Google Connected: #{context.user.google_connected}
    - Gmail Available: #{context.user.gmail_available}
    - Calendar Available: #{context.user.calendar_available}

    Available Actions: #{Enum.join(context.available_actions, ", ")}

    Recent Conversation:
    #{context.conversation}

    Instructions:
    - If the user asks about Gmail or emails and Gmail is available, you can actually access their emails and perform actions.
    - If the user asks about Calendar or events and Calendar is available, you can actually access their calendar and perform actions.
    - If the user asks for specific data (like "find emails with BCG"), and you have access, actually search and provide the results.
    - If you don't have access to a service, explain what you can do and suggest they connect their account.
    - Be helpful and intelligent in your responses.
    """
  end

  # Build AI prompt for automation setup
  defp build_automation_prompt(user_message, context) do
    """
    You are an intelligent AI assistant that can set up automation rules.
    The user wants to create an automation: "#{user_message}"

    User Context:
    - Name: #{context.user.name}
    - Email: #{context.user.email}
    - Google Connected: #{context.user.google_connected}
    - Gmail Available: #{context.user.gmail_available}
    - Calendar Available: #{context.user.calendar_available}

    Available Triggers: calendar_event_created, calendar_event_updated, calendar_event_deleted, email_received, hubspot_contact_created
    Available Actions: send_email, create_calendar_event, add_note, search_emails

    Instructions:
    1. Analyze the user's automation request
    2. Extract the trigger condition and the action to perform
    3. Provide a JSON response with the following structure:
    {
      "automation": {
        "name": "Descriptive name for this automation",
        "trigger": {
          "type": "calendar_event_created|email_received|hubspot_contact_created",
          "conditions": {
            // Trigger-specific conditions
          }
        },
        "action": {
          "type": "send_email|create_calendar_event|add_note|search_emails",
          "params": {
            // Action-specific parameters
          }
        },
        "description": "What this automation does"
      },
      "response": "User-friendly explanation of what automation was set up"
    }

    Be intelligent and contextual. If the user says "When I add an event in my calendar, send an email to attendees",
    the trigger should be "calendar_event_created" and the action should be "send_email" to the attendees.
    """
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

  # Execute AI instructions
  defp execute_ai_instructions(user, conversation_id, ai_response, user_message, context) do
    case parse_ai_response(ai_response) do
      {:ok, parsed} ->
        # Check if we have actions to execute
        actions = parsed["actions"] || []

        if length(actions) > 0 do
          # Execute each action
          results = Enum.map(actions, fn action ->
            execute_ai_action(user, conversation_id, action, context)
          end)

          # Create response
          response_text = parsed["response"] || "I've completed the requested task."
          create_agent_response(user, conversation_id, response_text, "action")
        else
          # No actions found, try direct Gmail/Calendar fallback
          IO.puts("DEBUG: No actions in AI response, trying direct fallback")
          execute_direct_fallback(user, conversation_id, user_message, context)
        end

      {:error, reason} ->
        IO.puts("Failed to parse AI response: #{reason}")
        execute_direct_fallback(user, conversation_id, user_message, context)
    end
  end

  # Direct fallback for Gmail/Calendar requests when AI fails
  defp execute_direct_fallback(user, conversation_id, user_message, context) do
    message_down = String.downcase(user_message)

    cond do
      # Handle recent emails request
      String.contains?(message_down, "recent") and String.contains?(message_down, "email") ->
        IO.puts("DEBUG: Direct fallback - getting recent emails")
        case Gmail.get_recent_emails(user, 10) do
          {:ok, emails} ->
            if length(emails) > 0 do
              email_summary = Enum.take(emails, 5)
              |> Enum.map(fn email ->
                "• #{email.subject} (from: #{email.from})"
              end)
              |> Enum.join("\n")

              response = "Here are your recent emails:\n\n#{email_summary}"
              if length(emails) > 5 do
                response = response <> "\n\n... and #{length(emails) - 5} more emails"
              end
              create_agent_response(user, conversation_id, response, "action")
            else
              create_agent_response(user, conversation_id, "No recent emails found.", "action")
            end
          {:error, reason} ->
            create_agent_response(user, conversation_id, "I couldn't retrieve your recent emails: #{reason}", "error")
        end

      # Handle last sent email request
      String.contains?(message_down, "last") and String.contains?(message_down, "sent") ->
        IO.puts("DEBUG: Direct fallback - getting last sent email")
        case Gmail.search_emails(user, "in:sent") do
          {:ok, [email | _]} ->
            response = "Your last sent email:\n\n• Subject: #{email.subject}\n• To: #{email.to}\n• Date: #{email.date}"
            create_agent_response(user, conversation_id, response, "action")
          {:ok, []} ->
            create_agent_response(user, conversation_id, "No sent emails found.", "action")
          {:error, reason} ->
            create_agent_response(user, conversation_id, "I couldn't retrieve your last sent email: #{reason}", "error")
        end

      # Handle general email search
      String.contains?(message_down, "email") and (String.contains?(message_down, "find") or String.contains?(message_down, "search") or String.contains?(message_down, "show")) ->
        IO.puts("DEBUG: Direct fallback - searching emails")
        # Extract search terms from the message
        search_terms = extract_search_terms(user_message)
        case Gmail.search_emails(user, search_terms) do
          {:ok, emails} ->
            if length(emails) > 0 do
              email_list = Enum.map(emails, fn email ->
                "• #{email.subject} - from: #{email.from}"
              end)
              |> Enum.join("\n")

              response = "Found #{length(emails)} emails:\n\n#{email_list}"
              create_agent_response(user, conversation_id, response, "action")
            else
              create_agent_response(user, conversation_id, "No emails found matching your search.", "action")
            end
          {:error, reason} ->
            create_agent_response(user, conversation_id, "I couldn't search your emails: #{reason}", "error")
        end

      # Default fallback
      true ->
        IO.puts("DEBUG: Using general fallback task")
        execute_fallback_task(user, conversation_id, user_message, context)
    end
  end

  # Extract search terms from user message
  defp extract_search_terms(message) do
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

  # Parse AI response JSON
  defp parse_ai_response(response) do
    # Try to extract JSON from the response
    case Regex.run(~r/\{.*\}/s, response) do
      [json_str] ->
        case Jason.decode(json_str) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, reason} -> {:error, "Invalid JSON: #{reason}"}
        end
      _ ->
        # If no JSON found, create a simple response
        {:ok, %{
          "actions" => [],
          "summary" => "AI response",
          "response" => response
        }}
    end
  end

  # Execute a single AI action
  defp execute_ai_action(user, conversation_id, action, context) do
    case action["type"] do
      "send_email" ->
        execute_email_action(user, conversation_id, action["params"], context)

      "create_calendar_event" ->
        execute_calendar_action(user, conversation_id, action["params"], context)

      "find_contact" ->
        execute_contact_action(user, conversation_id, action["params"], context)

      "search_emails" ->
        execute_search_action(user, conversation_id, action["params"], context)

      "get_emails" ->
        execute_get_emails_action(user, conversation_id, action["params"], context)

      "list_emails" ->
        execute_list_emails_action(user, conversation_id, action["params"], context)

      "compose_draft" ->
        execute_draft_action(user, conversation_id, action["params"], context)

      "get_recent_emails" ->
        execute_get_recent_emails_action(user, conversation_id, action["params"], context)

      _ ->
        {:error, "Unknown action type: #{action["type"]}"}
    end
  end

  # Execute email action
  defp execute_email_action(user, conversation_id, params, context) do
    to = params["to"] || params["recipient"]
    subject = params["subject"] || "No Subject"
    body = params["body"] || params["content"] || "Hello,\n\nBest regards,\n#{context.user.name}"

    if context.user.gmail_available do
      case Gmail.send_email(user, to, subject, body) do
        {:ok, _} -> {:ok, "Email sent to #{to}"}
        {:error, reason} -> {:error, "Failed to send email: #{reason}"}
      end
    else
      {:error, "Gmail not available"}
    end
  end

  # Execute calendar action
  defp execute_calendar_action(user, conversation_id, params, context) do
    title = params["title"] || params["subject"] || "Meeting"
    description = params["description"] || params["body"] || "Auto-created event"
    start_time = params["start_time"] || params["time"]
    end_time = params["end_time"] ||
      case DateTime.from_iso8601(start_time) do
        {:ok, start_dt, _} -> DateTime.add(start_dt, 3600, :second) |> DateTime.to_iso8601()
        _ -> start_time
      end
    attendees = params["attendees"] || []

    if context.user.calendar_available do
      event_data = %{
        "title" => title,
        "description" => description,
        "start_time" => start_time,
        "end_time" => end_time,
        "attendees" => attendees
      }

      case Calendar.create_event(user, event_data) do
        {:ok, _} -> {:ok, "Calendar event created: #{title}"}
        {:error, reason} -> {:error, "Failed to create event: #{reason}"}
      end
    else
      {:error, "Calendar not available"}
    end
  end

  # Execute contact action
  defp execute_contact_action(user, conversation_id, params, context) do
    name = params["name"] || params["contact"]

    if context.user.google_connected do
      case GoogleContacts.find_contact_by_name(user, name) do
        {:ok, contact} -> {:ok, "Found contact: #{contact.name}"}
        {:error, reason} -> {:error, "Contact not found: #{reason}"}
      end
    else
      {:error, "Google contacts not available"}
    end
  end

  # Execute search action
  defp execute_search_action(user, conversation_id, params, context) do
    query = params["query"] || params["search"]

    if context.user.gmail_available do
      case Gmail.search_emails(user, query) do
        {:ok, emails} -> {:ok, "Found #{length(emails)} emails"}
        {:error, reason} -> {:error, "Search failed: #{reason}"}
      end
    else
      {:error, "Gmail not available"}
    end
  end

  # Execute get emails action
  defp execute_get_emails_action(user, conversation_id, params, context) do
    query = params["query"] || params["search"] || params["keyword"] || ""

    if context.user.gmail_available do
      case Gmail.search_emails(user, query) do
        {:ok, emails} ->
          if length(emails) > 0 do
            email_summary = Enum.take(emails, 5)
            |> Enum.map(fn email ->
              "• #{email.subject} (from: #{email.from})"
            end)
            |> Enum.join("\n")

            response = "Found #{length(emails)} emails matching '#{query}':\n\n#{email_summary}"
            if length(emails) > 5 do
              response = response <> "\n\n... and #{length(emails) - 5} more emails"
            end
            {:ok, response}
          else
            {:ok, "No emails found matching '#{query}'"}
          end
        {:error, reason} -> {:error, "Failed to search emails: #{reason}"}
      end
    else
      {:error, "Gmail not available"}
    end
  end

  # Execute list emails action
  defp execute_list_emails_action(user, conversation_id, params, context) do
    query = params["query"] || params["search"] || params["keyword"] || ""

    if context.user.gmail_available do
      case Gmail.search_emails(user, query) do
        {:ok, emails} ->
          if length(emails) > 0 do
            email_list = Enum.map(emails, fn email ->
              "• #{email.subject} - from: #{email.from} (#{email.date})"
            end)
            |> Enum.join("\n")

            {:ok, "Emails matching '#{query}':\n\n#{email_list}"}
          else
            {:ok, "No emails found matching '#{query}'"}
          end
        {:error, reason} -> {:error, "Failed to list emails: #{reason}"}
      end
    else
      {:error, "Gmail not available"}
    end
  end

  # Execute draft action
  defp execute_draft_action(user, conversation_id, params, context) do
    to = params["to"] || params["recipient"]
    subject = params["subject"] || "Draft"
    body = params["body"] || params["content"] || "Draft content"

    if context.user.gmail_available do
      case Gmail.compose_draft(user, to, subject, body) do
        {:ok, _} -> {:ok, "Draft created"}
        {:error, reason} -> {:error, "Failed to create draft: #{reason}"}
      end
    else
      {:error, "Gmail not available"}
    end
  end

  # Execute get recent emails action
  defp execute_get_recent_emails_action(user, conversation_id, params, context) do
    max_results = params["max_results"] || 10

    if context.user.gmail_available do
      case Gmail.get_recent_emails(user, max_results) do
        {:ok, emails} ->
          if length(emails) > 0 do
            email_summary = Enum.take(emails, 5)
            |> Enum.map(fn email ->
              "• #{email.subject} (from: #{email.from})"
            end)
            |> Enum.join("\n")

            response = "Here are your recent emails:\n\n#{email_summary}"
            if length(emails) > 5 do
              response = response <> "\n\n... and #{length(emails) - 5} more emails"
            end
            {:ok, response}
          else
            {:ok, "No recent emails found."}
          end
        {:error, reason} -> {:error, "Failed to get recent emails: #{reason}"}
      end
    else
      {:error, "Gmail not available"}
    end
  end

  # Fallback task execution - direct action without AI, no suggestions, no drafts
  defp execute_fallback_task(user, conversation_id, user_message, context) do
    # Extract email address
    email_regex = ~r/([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})/
    email = case Regex.run(email_regex, user_message) do
      [_, email] -> email
      _ -> nil
    end

    # Extract subject (after 'about' or 'regarding')
    subject = case Regex.run(~r/(?:about|regarding)\s+([\w\s\d\-\.,!]+?)(?:\s+and|\s+in|\s+from|$)/i, user_message) do
      [_, subj] -> String.trim(subj)
      _ -> "Meeting"
    end

    # Extract time (e.g., 'in 4 hours')
    time_info = case Regex.run(~r/in (\d+) hours?/, user_message) do
      [_, hours] ->
        {:ok, dt} = DateTime.now("Etc/UTC")
        DateTime.add(dt, String.to_integer(hours) * 3600, :second)
      _ -> nil
    end

    # Compose email body
    email_body =
      "Hello,\n\nI would like to schedule a meeting regarding #{subject}.\n\nBest regards,\n#{context.user.name}"

    results = []

    # Send email if possible
    results =
      if email && context.user.gmail_available do
        case Gmail.send_email(user, email, subject, email_body) do
          {:ok, _} -> results ++ ["[DEBUG-ACTION] Email sent to #{email} (subject: #{subject})"]
          {:error, reason} -> results ++ ["[DEBUG-ACTION] Failed to send email: #{reason}"]
        end
      else
        results
      end

    # Add calendar event if possible
    results =
      if time_info && context.user.calendar_available && email do
        end_time = DateTime.add(time_info, 3600, :second)
        event_data = %{
          "title" => subject,
          "description" => "Meeting about #{subject}",
          "start_time" => DateTime.to_iso8601(time_info),
          "end_time" => DateTime.to_iso8601(end_time),
          "attendees" => [email]
        }

        case Calendar.create_event(user, event_data) do
          {:ok, _} -> results ++ ["[DEBUG-ACTION] Calendar event created for #{subject} at #{DateTime.to_string(time_info)}"]
          {:error, reason} -> results ++ ["[DEBUG-ACTION] Failed to create calendar event: #{reason}"]
        end
      else
        results
      end

    # Respond with only what was done
    response =
      cond do
        results == [] -> "[DEBUG-ACTION] Could not extract enough information to perform the requested task. Please specify an email and time."
        true -> Enum.join(results, "\n")
      end

    create_agent_response(user, conversation_id, response, "direct_action")
  end

  # Parse AI response and set up automation
  defp parse_and_setup_automation(user, conversation_id, ai_response, user_message, context) do
    case parse_automation_response(ai_response) do
      {:ok, automation_data} ->
        # Create the automation rule
        case create_automation_rule(user, automation_data["automation"]) do
          {:ok, rule} ->
            response = automation_data["response"] || "I've set up the automation: #{automation_data["automation"]["description"]}"
            create_agent_response(user, conversation_id, response, "automation_created")

          {:error, reason} ->
            create_agent_response(user, conversation_id, "Failed to create automation: #{reason}", "error")
        end

      {:error, reason} ->
        IO.puts("Failed to parse automation response: #{reason}")
        create_agent_response(user, conversation_id, "I couldn't understand how to set up that automation. Please try being more specific.", "error")
    end
  end

  # Parse automation response JSON
  defp parse_automation_response(response) do
    case Regex.run(~r/\{.*\}/s, response) do
      [json_str] ->
        case Jason.decode(json_str) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, reason} -> {:error, "Invalid JSON: #{reason}"}
        end
      _ ->
        {:error, "No JSON found in response"}
    end
  end

  # Create automation rule in database
  defp create_automation_rule(user, automation) do
    instruction = """
    Automation: #{automation["name"]}
    Trigger: #{automation["trigger"]["type"]}
    Action: #{automation["action"]["type"]}
    Description: #{automation["description"]}

    When #{automation["trigger"]["type"]} occurs, perform #{automation["action"]["type"]} with params: #{inspect(automation["action"]["params"])}
    """

    AgentInstruction.create(%{
      user_id: user.id,
      instruction: instruction,
      trigger_type: automation["trigger"]["type"],
      conditions: automation["trigger"]["conditions"] || %{},
      is_active: true
    })
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
end
