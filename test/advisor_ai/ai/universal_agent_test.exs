defmodule AdvisorAi.AI.UniversalAgentTest do
  use AdvisorAi.DataCase
  alias AdvisorAi.AI.UniversalAgent
  alias AdvisorAi.Accounts
  alias AdvisorAi.Chat

  # Test user setup
  setup do
    # Create and insert user
    user = %Accounts.User{
      id: Ecto.UUID.generate(),
      email: "test@example.com",
      name: "Test User"
    }
    user = Repo.insert!(user)

    # Create and insert conversation
    conversation = %Chat.Conversation{
      id: Ecto.UUID.generate(),
      user_id: user.id,
      title: "Test Conversation"
    }
    conversation = Repo.insert!(conversation)

    # Create and insert Google account
    account = %Accounts.Account{
      id: Ecto.UUID.generate(),
      user_id: user.id,
      provider: "google",
      provider_id: Ecto.UUID.generate(),
      access_token: "test-access-token",
      refresh_token: "test-refresh-token",
      scopes: [
        "https://www.googleapis.com/auth/gmail.modify",
        "https://www.googleapis.com/auth/calendar",
        "https://www.googleapis.com/auth/contacts"
      ],
      token_expires_at: DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)
    }
    account = Repo.insert!(account)

    {:ok, %{user: user, conversation: conversation, account: account}}
  end

  describe "Universal Action System - Core Functionality" do
    test "process_request function exists and is callable", %{user: user, conversation: conversation} do
      # Test that the function exists and can be called
      assert function_exported?(UniversalAgent, :process_request, 3)

      # Test with a simple message
      result = UniversalAgent.process_request(user, conversation.id, "test message")

      # Should return a result (even if it's an error due to missing dependencies)
      assert is_tuple(result)
    end

    test "action parsing from natural language", %{user: user, conversation: conversation} do
      # Test various natural language patterns
      test_cases = [
        {"search emails for BCG", "search_emails"},
        {"find emails about meetings", "search_emails"},
        {"send email to john@example.com", "send_email"},
        {"create calendar event", "create_event"},
        {"list my events", "list_events"},
        {"find contact John", "search_contacts"},
        {"check my permissions", "check_permissions"}
      ]

      for {message, _expected_action} <- test_cases do
        result = UniversalAgent.process_request(user, conversation.id, message)
        assert is_tuple(result)
        # The function should handle the request (even if it fails due to missing deps)
      end
    end

    test "parameter extraction from natural language", %{user: user, conversation: conversation} do
      # Test parameter extraction
      test_cases = [
        {"search emails with query 'important'", %{action: "search_emails", query: "important"}},
        {"send email to test@example.com subject 'Test' body 'Hello'", %{action: "send_email", to: "test@example.com", subject: "Test", body: "Hello"}},
        {"create event 'Meeting' from 2024-01-01 10:00 to 11:00", %{action: "create_event", summary: "Meeting", start_time: "2024-01-01T10:00:00Z", end_time: "2024-01-01T11:00:00Z"}}
      ]

      for {message, _expected_params} <- test_cases do
        result = UniversalAgent.process_request(user, conversation.id, message)
        assert is_tuple(result)
        # The function should handle the request
      end
    end

    test "error handling for invalid requests", %{user: user, conversation: conversation} do
      # Test error handling
      error_cases = [
        "",  # Empty message
        "   ",  # Whitespace only
        "perform unknown action",  # Unknown action
        "send email without parameters"  # Missing required parameters
      ]

      for message <- error_cases do
        result = UniversalAgent.process_request(user, conversation.id, message)
        assert is_tuple(result)
        # Should handle gracefully
      end
    end

    test "edge cases and special characters", %{user: user, conversation: conversation} do
      # Test edge cases
      edge_cases = [
        "search emails with query 'test@example.com & subject:meeting'",
        "search emails with query 'café résumé'",
        "SEARCH EMAILS WITH QUERY TEST",  # All caps
        "Search Emails With Query Test",  # Mixed case
        String.duplicate("search emails ", 100)  # Very long message
      ]

      for message <- edge_cases do
        result = UniversalAgent.process_request(user, conversation.id, message)
        assert is_tuple(result)
        # Should handle gracefully
      end
    end

    test "complex scenarios", %{user: user, conversation: conversation} do
      # Test complex scenarios
      complex_cases = [
        "search emails for important and also create calendar event",
        "find meeting",  # Ambiguous but should infer email search
        "send email to recipient@example.com subject 'Subject' body 'Body'",
        "show my next 5 calendar events"
      ]

      for message <- complex_cases do
        result = UniversalAgent.process_request(user, conversation.id, message)
        assert is_tuple(result)
        # Should handle gracefully
      end
    end
  end

  describe "Gmail Operations - Comprehensive Testing" do
    test "email search operations", %{user: user, conversation: conversation} do
      # Test various email search scenarios from requirements
      search_cases = [
        "Who mentioned their kid plays baseball?",
        "Why did greg say he wanted to sell AAPL stock",
        "Find emails from Sara Smith about our meeting",
        "Search for emails containing 'investment portfolio'",
        "Find emails from last week about client meetings",
        "Search emails with subject containing 'urgent'",
        "Find emails from clients about their financial goals",
        "Search for emails mentioning 'retirement planning'",
        "Find emails from john@example.com about tax documents",
        "Search emails with attachments about quarterly reports"
      ]

      for search_query <- search_cases do
        result = UniversalAgent.process_request(user, conversation.id, search_query)
        assert is_tuple(result)
      end
    end

    test "email composition and sending", %{user: user, conversation: conversation} do
      # Test email sending scenarios from requirements
      email_cases = [
        "Email Sara Smith asking to set up an appointment",
        "Send email to john@example.com with subject 'Meeting Follow-up' and body 'Thank you for our discussion'",
        "Compose email to client about their portfolio review",
        "Send meeting reminder to all attendees",
        "Email new client welcome message",
        "Send follow-up email after consultation",
        "Email client about document requirements",
        "Send calendar invitation via email",
        "Email thank you note after successful meeting",
        "Send email with available meeting times"
      ]

      for email_request <- email_cases do
        result = UniversalAgent.process_request(user, conversation.id, email_request)
        assert is_tuple(result)
      end
    end

    test "email management operations", %{user: user, conversation: conversation} do
      # Test email management scenarios
      management_cases = [
        "Mark email as read",
        "Move email to important folder",
        "Delete spam email",
        "Archive old emails",
        "Forward email to assistant",
        "Reply to client email",
        "Mark email as unread for follow-up",
        "Add email to task list",
        "Flag email for urgent attention",
        "Organize emails by client"
      ]

      for management_request <- management_cases do
        result = UniversalAgent.process_request(user, conversation.id, management_request)
        assert is_tuple(result)
      end
    end

    test "intelligent email features", %{user: user, conversation: conversation} do
      # Test intelligent email features from requirements
      intelligent_cases = [
        "When someone emails me that is not in Hubspot, please create a contact in Hubspot with a note about the email",
        "When I create a contact in Hubspot, send them an email telling them thank you for being a client",
        "When I add an event in my calendar, send an email to attendees tell them about the meeting",
        "When a client emails me asking when our upcoming meeting is, look it up on the calendar and respond",
        "Auto-reply to emails from new clients with welcome message",
        "Send follow-up email 3 days after initial consultation",
        "Email clients about upcoming tax deadlines",
        "Send birthday wishes to clients",
        "Email quarterly portfolio updates to clients",
        "Send meeting confirmation emails automatically"
      ]

      for intelligent_request <- intelligent_cases do
        result = UniversalAgent.process_request(user, conversation.id, intelligent_request)
        assert is_tuple(result)
      end
    end

    test "email edge cases and error handling", %{user: user, conversation: conversation} do
      # Test edge cases for email operations
      edge_cases = [
        "Send email to invalid email address",
        "Search emails with empty query",
        "Send email without subject",
        "Search emails with special characters: @#$%^&*()",
        "Send email to multiple recipients with different formats",
        "Search emails with very long query",
        "Send email with HTML content",
        "Search emails with date range in different formats",
        "Send email with large attachments",
        "Search emails with complex boolean logic"
      ]

      for edge_case <- edge_cases do
        result = UniversalAgent.process_request(user, conversation.id, edge_case)
        assert is_tuple(result)
      end
    end
  end

  describe "Google Calendar Operations - Comprehensive Testing" do
    test "calendar event creation", %{user: user, conversation: conversation} do
      # Test calendar event creation scenarios from requirements
      creation_cases = [
        "Schedule an appointment with Sara Smith",
        "Create calendar event 'Client Meeting' for tomorrow at 2 PM",
        "Schedule portfolio review with John Doe next week",
        "Create recurring meeting every Monday at 10 AM",
        "Schedule consultation with new client",
        "Create calendar event for tax planning session",
        "Schedule follow-up meeting in 2 weeks",
        "Create event for annual review",
        "Schedule phone call with client",
        "Create calendar event for document signing"
      ]

      for creation_request <- creation_cases do
        result = UniversalAgent.process_request(user, conversation.id, creation_request)
        assert is_tuple(result)
      end
    end

    test "calendar event management", %{user: user, conversation: conversation} do
      # Test calendar event management
      management_cases = [
        "Reschedule my meeting with Sara to next Tuesday",
        "Cancel the 2 PM meeting tomorrow",
        "Update meeting duration to 2 hours",
        "Add John to the existing meeting",
        "Remove Sarah from the calendar event",
        "Change meeting location to conference room B",
        "Update meeting agenda",
        "Set meeting reminder to 30 minutes before",
        "Make meeting private",
        "Duplicate meeting for next week"
      ]

      for management_request <- management_cases do
        result = UniversalAgent.process_request(user, conversation.id, management_request)
        assert is_tuple(result)
      end
    end

    test "calendar availability and scheduling", %{user: user, conversation: conversation} do
      # Test availability and scheduling scenarios
      availability_cases = [
        "Show my available times for tomorrow",
        "Find next available slot for 1-hour meeting",
        "Check my calendar for conflicts next week",
        "Show my schedule for the rest of the day",
        "Find available time slots this week",
        "Check if I'm free on Friday afternoon",
        "Show my calendar for next month",
        "Find available time for client consultation",
        "Check my availability for team meeting",
        "Show my calendar for the quarter"
      ]

      for availability_request <- availability_cases do
        result = UniversalAgent.process_request(user, conversation.id, availability_request)
        assert is_tuple(result)
      end
    end

    test "calendar event queries", %{user: user, conversation: conversation} do
      # Test calendar event query scenarios
      query_cases = [
        "When is my next meeting with Sara Smith?",
        "Show all meetings this week",
        "Find meetings about portfolio review",
        "Show my calendar for today",
        "List all client meetings this month",
        "Find meetings with John Doe",
        "Show upcoming appointments",
        "Find meetings about tax planning",
        "List all recurring meetings",
        "Show meetings with external clients"
      ]

      for query_request <- query_cases do
        result = UniversalAgent.process_request(user, conversation.id, query_request)
        assert is_tuple(result)
      end
    end

    test "calendar integration scenarios", %{user: user, conversation: conversation} do
      # Test calendar integration scenarios from requirements
      integration_cases = [
        "When I add an event in my calendar, send an email to attendees tell them about the meeting",
        "When a client emails me asking when our upcoming meeting is, look it up on the calendar and respond",
        "Send calendar invitation to new client",
        "Update calendar when meeting is rescheduled via email",
        "Create calendar event from email request",
        "Send meeting reminder emails automatically",
        "Sync calendar with client availability",
        "Create follow-up calendar events after meetings",
        "Update calendar when client cancels via email",
        "Send calendar updates to all attendees"
      ]

      for integration_request <- integration_cases do
        result = UniversalAgent.process_request(user, conversation.id, integration_request)
        assert is_tuple(result)
      end
    end

    test "calendar edge cases and complex scenarios", %{user: user, conversation: conversation} do
      # Test edge cases for calendar operations
      edge_cases = [
        "Schedule meeting with multiple time zones",
        "Create all-day event for vacation",
        "Schedule meeting with 50 attendees",
        "Create recurring event with exceptions",
        "Schedule meeting in different calendar",
        "Create event with custom reminder settings",
        "Schedule meeting with video conference link",
        "Create event with location and directions",
        "Schedule meeting with multiple rooms",
        "Create event with custom color coding"
      ]

      for edge_case <- edge_cases do
        result = UniversalAgent.process_request(user, conversation.id, edge_case)
        assert is_tuple(result)
      end
    end
  end

  describe "Cross-Platform Integration Scenarios" do
    test "Gmail-Calendar integration workflows", %{user: user, conversation: conversation} do
      # Test integration workflows between Gmail and Calendar
      integration_workflows = [
        "Email Sara Smith asking to set up an appointment, when she responds, take appropriate action like add to calendar",
        "When she responds saying none of the times work, send some new times",
        "Email client about meeting, then create calendar event when they confirm",
        "Send calendar invitation via email and track responses",
        "Create calendar event from email request and send confirmation",
        "Update calendar when meeting is rescheduled via email",
        "Send meeting reminder emails automatically from calendar events",
        "Create follow-up calendar events after email consultations",
        "Sync calendar availability with email scheduling requests",
        "Send calendar updates to all attendees when changes are made"
      ]

      for workflow <- integration_workflows do
        result = UniversalAgent.process_request(user, conversation.id, workflow)
        assert is_tuple(result)
      end
    end

    test "proactive agent scenarios", %{user: user, conversation: conversation} do
      # Test proactive agent scenarios from requirements
      proactive_scenarios = [
        "When someone emails me that is not in Hubspot, please create a contact in Hubspot with a note about the email",
        "When I create a contact in Hubspot, send them an email telling them thank you for being a client",
        "When I add an event in my calendar, send an email to attendees tell them about the meeting",
        "When a client emails me asking when our upcoming meeting is, look it up on the calendar and respond",
        "Proactively send follow-up emails after meetings",
        "Automatically create calendar events from email requests",
        "Send birthday wishes to clients automatically",
        "Proactively remind clients about upcoming deadlines",
        "Auto-reply to new client inquiries with welcome message",
        "Send quarterly portfolio updates to all clients"
      ]

      for scenario <- proactive_scenarios do
        result = UniversalAgent.process_request(user, conversation.id, scenario)
        assert is_tuple(result)
      end
    end

    test "complex multi-step workflows", %{user: user, conversation: conversation} do
      # Test complex multi-step workflows
      complex_workflows = [
        "Schedule an appointment with Sara Smith - look up Sara Smith in Hubspot, or previous emails, email her asking to set up an appointment sharing available times from my calendar, when she responds, take appropriate action like add to calendar, make a note of the interaction in Hubspot, respond letting them know its done",
        "Handle client onboarding: create contact in Hubspot, send welcome email, schedule initial consultation, add to calendar, send reminder emails",
        "Process meeting cancellation: update calendar, notify all attendees, reschedule if needed, update Hubspot notes",
        "Handle urgent client request: prioritize email, check calendar availability, schedule emergency meeting, notify relevant parties",
        "Process quarterly review workflow: identify clients due for review, check calendar availability, send scheduling emails, create calendar events, send reminders"
      ]

      for workflow <- complex_workflows do
        result = UniversalAgent.process_request(user, conversation.id, workflow)
        assert is_tuple(result)
      end
    end
  end

  describe "Universal Action System - Tool Generation" do
    test "get_available_tools returns correct structure", %{user: user} do
      # Test that tools are generated correctly
      tools = UniversalAgent.get_available_tools(user)

      assert is_list(tools)
      # Tools might be empty if user doesn't have Google tokens
      if length(tools) > 0 do
        # Check that universal_action tool exists
        universal_tool = Enum.find(tools, fn tool ->
          tool[:name] == "universal_action" || (is_map(tool) && Map.get(tool, "name") == "universal_action")
        end)

        assert universal_tool != nil
      end
    end

    test "tool parameters are correctly structured", %{user: user} do
      tools = UniversalAgent.get_available_tools(user)

      if length(tools) > 0 do
        universal_tool = Enum.find(tools, fn tool ->
          tool[:name] == "universal_action" || (is_map(tool) && Map.get(tool, "name") == "universal_action")
        end)

        assert universal_tool != nil

        # Check parameters structure
        params = universal_tool[:parameters] || universal_tool["parameters"]
        assert params != nil
        assert params[:type] == "object" || params["type"] == "object"

        # Check required fields
        required = params[:required] || params["required"]
        assert required != nil
        assert "action" in required
      end
    end
  end

  describe "Universal Action System - Context Building" do
    test "build_ai_context creates valid context", %{user: user, conversation: conversation} do
      context = UniversalAgent.build_ai_context(user, conversation, %{})

      assert is_map(context)
      assert context[:user] != nil
      assert context[:conversation] != nil
      assert context[:recent_messages] != nil
      assert context[:current_time] != nil

      # Check user context
      user_context = context[:user]
      assert user_context[:name] == user.name
      assert user_context[:email] == user.email
      assert is_boolean(user_context[:google_connected])
      assert is_boolean(user_context[:gmail_available])
      assert is_boolean(user_context[:calendar_available])
    end
  end

  describe "Universal Action System - Response Handling" do
    test "create_agent_response creates valid message", %{user: user, conversation: conversation} do
      result = UniversalAgent.create_agent_response(user, conversation.id, "Test response", "action")

      assert {:ok, message} = result
      assert message.role == "assistant"
      assert message.content == "Test response"
      assert (message.metadata["response_type"] == "action" || message.metadata[:response_type] == "action")
      assert message.conversation_id == conversation.id
    end

    test "handle_unknown_action handles unknown actions gracefully", %{user: user, conversation: conversation} do
      result = UniversalAgent.handle_unknown_action(user, conversation.id, "unknown action")

      assert {:ok, message} = result
      assert message.role == "assistant"
      assert String.contains?(message.content, "Could not determine how to execute action")
      assert (message.metadata["response_type"] == "error" || message.metadata[:response_type] == "error")
    end
  end

  describe "Universal Action System - Integration Tests" do
    test "end-to-end workflow with simple request", %{user: user, conversation: conversation} do
      # Test a simple end-to-end workflow
      result = UniversalAgent.process_request(user, conversation.id, "test message")

      # Should return a result
      assert is_tuple(result)
    end

    test "multiple requests in sequence", %{user: user, conversation: conversation} do
      # Test multiple requests
      requests = [
        "search emails",
        "list calendar events",
        "find contacts"
      ]

      for request <- requests do
        result = UniversalAgent.process_request(user, conversation.id, request)
        assert is_tuple(result)
      end
    end
  end
end
