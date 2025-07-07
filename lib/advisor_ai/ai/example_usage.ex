defmodule AdvisorAi.AI.ExampleUsage do
  @moduledoc """
  Examples of how the intelligent agent can handle any user request dynamically.

  This demonstrates the power of the new approach vs the old hardcoded tools.
  """

  alias AdvisorAi.AI.{IntelligentAgent, WorkflowGenerator}

  @doc """
  Example 1: Simple email request
  Old approach: Would need hardcoded send_email tool
  New approach: AI analyzes and determines what to do
  """
  def example_send_email(user, conversation_id) do
    request = "Send an email to john@example.com about our meeting tomorrow at 2pm"

    # The intelligent agent will:
    # 1. Analyze the request
    # 2. Extract email address, subject, and body
    # 3. Call the appropriate Gmail API
    # 4. Generate a natural response

    IntelligentAgent.process_request(user, conversation_id, request)
  end

  @doc """
  Example 2: Complex workflow request
  Old approach: Would need multiple hardcoded tools and manual orchestration
  New approach: AI generates a complete workflow automatically
  """
  def example_client_onboarding(user, conversation_id) do
    request =
      "I just received an email from a new client Sarah Johnson at sarah@techstartup.com. She wants to discuss investment options. Please onboard her properly."

    # The intelligent agent will:
    # 1. Analyze the request and understand it's a client onboarding
    # 2. Generate a workflow with multiple steps:
    #    - Search for existing emails from Sarah
    #    - Create HubSpot contact
    #    - Schedule initial consultation meeting
    #    - Send welcome email
    # 3. Execute the workflow with proper error handling
    # 4. Provide a comprehensive response

    IntelligentAgent.process_request(user, conversation_id, request)
  end

  @doc """
  Example 3: Ambiguous request that requires intelligence
  Old approach: Would fail or require manual intervention
  New approach: AI figures out what the user means
  """
  def example_ambiguous_request(user, conversation_id) do
    request = "Follow up with that client from last week about the portfolio review"

    # The intelligent agent will:
    # 1. Analyze the request and understand it needs context
    # 2. Search emails from last week to find the client
    # 3. Extract the client's information
    # 4. Generate appropriate follow-up content
    # 5. Send the email
    # 6. Add a note to HubSpot

    IntelligentAgent.process_request(user, conversation_id, request)
  end

  @doc """
  Example 4: Multi-step business process
  Old approach: Would require custom code for each business process
  New approach: AI understands business context and creates workflows
  """
  def example_lead_qualification(user, conversation_id) do
    request =
      "I got an inquiry from a potential client interested in retirement planning. They mentioned they have $500k to invest. Please qualify them and set up a consultation."

    # The intelligent agent will:
    # 1. Understand this is a lead qualification process
    # 2. Generate a workflow:
    #    - Create HubSpot contact with qualification notes
    #    - Send qualification questionnaire
    #    - Schedule qualification call
    #    - Set up follow-up reminders
    # 3. Execute the workflow
    # 4. Provide status updates

    IntelligentAgent.process_request(user, conversation_id, request)
  end

  @doc """
  Example 5: Creative request that combines multiple systems
  Old approach: Would require custom integration code
  New approach: AI dynamically combines available APIs
  """
  def example_cross_system_request(user, conversation_id) do
    request =
      "I had a great meeting with ABC Corp today. Please send them a thank you email, add notes to their contact record, and schedule a follow-up meeting for next month."

    # The intelligent agent will:
    # 1. Search for ABC Corp in HubSpot
    # 2. Extract meeting details from calendar
    # 3. Generate personalized thank you email
    # 4. Send the email
    # 5. Add meeting notes to HubSpot contact
    # 6. Schedule follow-up meeting
    # 7. Send calendar invite

    IntelligentAgent.process_request(user, conversation_id, request)
  end

  @doc """
  Example 6: Error handling and fallbacks
  Old approach: Would fail completely if one step failed
  New approach: AI handles errors gracefully and provides alternatives
  """
  def example_error_handling(user, conversation_id) do
    request = "Send an email to invalid-email@ about our meeting"

    # The intelligent agent will:
    # 1. Try to send the email
    # 2. Detect the email is invalid
    # 3. Provide helpful error message
    # 4. Suggest alternatives (e.g., "Could you provide a valid email address?")
    # 5. Offer to draft the email for manual sending

    IntelligentAgent.process_request(user, conversation_id, request)
  end

  @doc """
  Example 7: Learning from context
  Old approach: Each request is isolated
  New approach: AI uses conversation history and RAG context
  """
  def example_contextual_request(user, conversation_id) do
    request = "Send them the proposal we discussed"

    # The intelligent agent will:
    # 1. Use conversation history to understand "them" refers to
    # 2. Use RAG to find the proposal document
    # 3. Extract the client's email from previous context
    # 4. Send the proposal with appropriate cover email
    # 5. Update HubSpot with the action taken

    IntelligentAgent.process_request(user, conversation_id, request)
  end

  @doc """
  Example 8: Proactive assistance
  Old approach: Only responds to explicit requests
  New approach: AI can be proactive based on patterns and instructions
  """
  def example_proactive_assistance(user, conversation_id) do
    request = "I'm going on vacation next week"

    # The intelligent agent will:
    # 1. Understand this is a vacation notification
    # 2. Generate a proactive workflow:
    #    - Set up out-of-office email
    #    - Reschedule upcoming meetings
    #    - Send notifications to important clients
    #    - Create follow-up tasks for when you return
    # 3. Execute the workflow
    # 4. Provide summary of actions taken

    IntelligentAgent.process_request(user, conversation_id, request)
  end

  @doc """
  Demonstrates the workflow generator for complex requests
  """
  def example_workflow_generation(user_request) do
    # Generate a workflow for any complex request
    case WorkflowGenerator.generate_workflow(user_request) do
      {:ok, workflow} ->
        IO.puts("Generated workflow: #{inspect(workflow, pretty: true)}")
        {:ok, workflow}

      {:error, reason} ->
        IO.puts("Failed to generate workflow: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Shows how the system can handle completely new types of requests
  without any code changes
  """
  def example_new_request_type(user, conversation_id) do
    request =
      "I need to prepare for my quarterly review with my manager. Can you help me gather all the client meetings and portfolio performance data from the last 3 months?"

    # This is a completely new type of request that wasn't pre-programmed.
    # The intelligent agent will:
    # 1. Analyze the request and understand it needs data gathering
    # 2. Generate a workflow to:
    #    - Search calendar for meetings in the last 3 months
    #    - Extract meeting details and outcomes
    #    - Gather portfolio performance data
    #    - Compile everything into a report
    # 3. Execute the workflow
    # 4. Provide a comprehensive summary

    IntelligentAgent.process_request(user, conversation_id, request)
  end
end
