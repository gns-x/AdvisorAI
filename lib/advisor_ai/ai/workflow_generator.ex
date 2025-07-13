defmodule AdvisorAi.AI.WorkflowGenerator do
  @moduledoc """
  Workflow Generator that can create complex multi-step workflows automatically.

  This module can:
  1. Analyze complex user requests
  2. Generate multi-step workflows
  3. Handle dependencies between actions
  4. Provide fallback strategies
  5. Learn from previous workflows
  """

  alias AdvisorAi.AI.GroqClient

  @workflow_templates %{
    "client_onboarding" => [
      %{
        "step" => 1,
        "action" => "search_emails",
        "params" => %{"query" => "client onboarding"},
        "description" => "Find existing onboarding emails",
        "fallback" => "create_contact"
      },
      %{
        "step" => 2,
        "action" => "create_contact",
        "params" => %{"email" => "extracted_email", "name" => "extracted_name"},
        "description" => "Create HubSpot contact",
        "depends_on" => 1
      },
      %{
        "step" => 3,
        "action" => "schedule_meeting",
        "params" => %{"title" => "Onboarding Call", "attendees" => "contact_email"},
        "description" => "Schedule onboarding meeting",
        "depends_on" => 2
      },
      %{
        "step" => 4,
        "action" => "send_email",
        "params" => %{"to" => "contact_email", "subject" => "Welcome!", "body" => "Welcome email"},
        "description" => "Send welcome email",
        "depends_on" => 3
      }
    ],
    "meeting_followup" => [
      %{
        "step" => 1,
        "action" => "search_emails",
        "params" => %{"query" => "meeting followup"},
        "description" => "Find meeting-related emails"
      },
      %{
        "step" => 2,
        "action" => "send_email",
        "params" => %{
          "to" => "attendee",
          "subject" => "Meeting Follow-up",
          "body" => "Follow-up content"
        },
        "description" => "Send follow-up email",
        "depends_on" => 1
      },
      %{
        "step" => 3,
        "action" => "add_note",
        "params" => %{"contact_id" => "contact_id", "note" => "Follow-up sent"},
        "description" => "Add note to contact",
        "depends_on" => 2
      }
    ],
    "lead_qualification" => [
      %{
        "step" => 1,
        "action" => "search_emails",
        "params" => %{"query" => "lead inquiry"},
        "description" => "Find lead inquiries"
      },
      %{
        "step" => 2,
        "action" => "create_contact",
        "params" => %{"email" => "lead_email", "name" => "lead_name"},
        "description" => "Create contact for lead",
        "depends_on" => 1
      },
      %{
        "step" => 3,
        "action" => "send_email",
        "params" => %{
          "to" => "lead_email",
          "subject" => "Thank you for your interest",
          "body" => "Qualification email"
        },
        "description" => "Send qualification email",
        "depends_on" => 2
      }
    ],
    "advanced_appointment_scheduling" => [
      %{
        "step" => 1,
        "action" => "search_contacts",
        "api" => "hubspot",
        "params" => %{"query" => "extracted_name_or_email"},
        "description" => "Look up the contact in HubSpot by name or email.",
        "fallback" => "search_emails",
        "extract_from" => %{
          "contact_email" => "first_contact_email",
          "contact_name" => "first_contact_name",
          "contact_id" => "first_contact_id"
        }
      },
      %{
        "step" => 2,
        "action" => "search_emails",
        "api" => "gmail",
        "params" => %{"query" => "extracted_name_or_email"},
        "description" => "If not found in HubSpot, search previous emails for the contact.",
        "depends_on" => 1,
        "extract_from" => %{
          "contact_email" => "email_contact_email",
          "contact_name" => "email_contact_name"
        }
      },
      %{
        "step" => 3,
        "action" => "get_availability",
        "api" => "calendar",
        "params" => %{"date" => "next_3_days", "duration_minutes" => 30},
        "description" => "Get available times from Google Calendar for the next 3 days.",
        "depends_on" => 2,
        "extract_from" => %{
          "available_times" => "calendar_available_times"
        }
      },
      %{
        "step" => 4,
        "action" => "send_email",
        "api" => "gmail",
        "params" => %{
          "to" => "contact_email",
          "subject" => "Let's set up an appointment",
          "body" =>
            "Here are my available times: {available_times}. Please reply with what works for you."
        },
        "description" => "Send an email to the contact proposing available times.",
        "depends_on" => 3
      },
      %{
        "step" => 5,
        "action" => "wait_for_reply",
        "api" => "gmail",
        "params" => %{"from" => "contact_email", "timeout_hours" => 48},
        "description" => "Wait for the contact's reply and analyze the response using LLM.",
        "depends_on" => 4,
        "extract_from" => %{
          "response_type" => "reply_analysis",
          "chosen_time" => "extracted_chosen_time",
          "needs_new_times" => "needs_new_times"
        }
      },
      %{
        "step" => 6,
        "action" => "conditional_schedule",
        "api" => "calendar",
        "params" => %{
          "condition" => "if_chosen_time_exists",
          "title" => "Appointment with {contact_name}",
          "attendees" => ["contact_email"],
          "start_time" => "chosen_time",
          "duration_minutes" => 30
        },
        "description" => "If a time is accepted, schedule the event in Google Calendar.",
        "depends_on" => 5
      },
      %{
        "step" => 7,
        "action" => "conditional_send_new_times",
        "api" => "gmail",
        "params" => %{
          "condition" => "if_needs_new_times",
          "to" => "contact_email",
          "subject" => "Alternative appointment times",
          "body" => "Here are some additional available times: {new_available_times}"
        },
        "description" => "If none of the times work, send new available times.",
        "depends_on" => 6
      },
      %{
        "step" => 8,
        "action" => "add_note",
        "api" => "hubspot",
        "params" => %{
          "contact_email" => "contact_email",
          "note_content" => "Appointment scheduling initiated. {appointment_status}"
        },
        "description" => "Add a note in HubSpot about the appointment scheduling process.",
        "depends_on" => 7
      },
      %{
        "step" => 9,
        "action" => "conditional_send_confirmation",
        "api" => "gmail",
        "params" => %{
          "condition" => "if_appointment_scheduled",
          "to" => "contact_email",
          "subject" => "Appointment Confirmed",
          "body" =>
            "Your appointment is confirmed for {chosen_time}. Looking forward to speaking with you!"
        },
        "description" => "Send a confirmation email to the contact if appointment was scheduled.",
        "depends_on" => 8
      }
    ]
  }

  def generate_workflow(user_request, context \\ "") do
    message_lower = String.downcase(user_request)

    if String.contains?(message_lower, "schedule an appointment") or
         String.contains?(message_lower, "set up a meeting") or
         String.contains?(message_lower, "book a call") or
         String.contains?(message_lower, "arrange a meeting") or
         String.contains?(message_lower, "schedule with") or
         String.contains?(message_lower, "meet with") do
      # Use LLM to generate a more sophisticated workflow for appointment scheduling
      system_prompt = """
      You are an expert workflow generator for appointment scheduling. Generate a detailed, flexible workflow that can handle edge cases.

      For appointment scheduling requests, create a workflow that:
      1. Extracts contact information (name/email) from the request
      2. Searches for the contact in HubSpot first, then falls back to email search
      3. Gets available calendar times (next 3-7 days, 30-60 minute slots)
      4. Sends a professional email with available times
      5. Waits for and analyzes the contact's response using LLM
      6. Handles multiple scenarios:
         - Contact accepts a time → schedule meeting + send confirmation
         - Contact rejects all times → get new times + send alternatives
         - Contact suggests different time → check availability + respond
         - Contact doesn't respond → send follow-up after 48 hours
      7. Adds appropriate notes to HubSpot throughout the process
      8. Uses conditional logic to handle different response types

      Available APIs and actions:
      - Gmail: search_emails, send_email, read_email, get_email_threads, wait_for_reply
      - Calendar: get_availability, create_event, list_events, check_availability
      - HubSpot: search_contacts, create_contact, add_note, update_contact

      Generate a JSON workflow with:
      1. "workflow_name": "Flexible Appointment Scheduling"
      2. "extracted_data": What to extract from the user request
      3. "steps": Array of workflow steps with:
         - "step": Step number
         - "action": Action to perform
         - "api": Which API to use (gmail, calendar, hubspot)
         - "params": Parameters (use placeholders like {contact_name}, {available_times})
         - "description": What this step does
         - "depends_on": Step number this depends on (optional)
         - "fallback": Alternative action if this fails (optional)
         - "condition": When to execute this step (optional)
         - "extract_from": What data to extract from previous steps (optional)
      4. "error_handling": How to handle failures and edge cases
      5. "llm_analysis": Steps that require LLM analysis (like interpreting email responses)

      User Request: "#{user_request}"
      Context: #{context}

      Respond with only the JSON workflow.
      """

      case GroqClient.chat_completion(
             messages: [
               %{role: "system", content: system_prompt},
               %{role: "user", content: user_request}
             ]
           ) do
        {:ok, %{"choices" => [%{"message" => %{"content" => response}}]}} ->
          case Jason.decode(response) do
            {:ok, workflow} ->
              # Validate and enhance the workflow
              enhanced_workflow = enhance_appointment_workflow(workflow, user_request)
              {:ok, enhanced_workflow}

            {:error, _} ->
              # Fallback to template
              {:ok, Map.get(@workflow_templates, "advanced_appointment_scheduling")}
          end

        {:error, reason} ->
          # Fallback to template
          {:ok, Map.get(@workflow_templates, "advanced_appointment_scheduling")}
      end
    else
      # Use AI to analyze the request and generate a workflow
      system_prompt = """
      You are an expert workflow generator. Analyze the user's request and generate a detailed workflow.

      For any request to schedule, set up, or arrange an appointment/meeting/call, you MUST generate a multi-step workflow that includes:
      1. Contact lookup in HubSpot (by name/email)
      2. If not found, search previous emails for the contact
      3. Get available times from Google Calendar
      4. Send an email to the contact proposing available times
      5. Wait for a reply and, based on the response, either schedule the event, propose new times, or add a note in HubSpot
      6. Add a note in HubSpot about the scheduled appointment
      7. Send a confirmation email to the contact
      8. Handle all steps with LLM-driven flexibility and fallback strategies

      Available actions:
      - Gmail: search_emails, send_email, read_email, get_email_threads
      - Calendar: get_availability, schedule_meeting, get_events, update_event, delete_event
      - HubSpot: search_contacts, create_contact, update_contact, add_note, get_deals

      CRITICAL: For any request about meetings, events, or calendar (e.g., 'list all my meetings', 'show my events', 'what meetings do I have', 'calendar for today'), you MUST use the Calendar API (get_events, schedule_meeting, etc.). Do NOT use HubSpot contacts for meetings or events.

      Examples:
      - 'list all my meetings' => use Calendar API get_events
      - 'show my events today' => use Calendar API get_events
      - 'schedule a meeting' => use Calendar API schedule_meeting
      - 'get calendar for today' => use Calendar API get_events

      Generate a JSON workflow with:
      1. \"workflow_name\": Descriptive name
      2. \"steps\": Array of workflow steps, each with:
         - \"step\": Step number
         - \"action\": Action to perform
         - \"api\": Which API to use (gmail, calendar, hubspot)
         - \"params\": Parameters for the action
         - \"description\": What this step does
         - \"depends_on\": Step number this depends on (optional)
         - \"fallback\": Alternative action if this fails (optional)
         - \"extract_from\": What data to extract from previous steps (optional)

      3. \"extractions\": What data to extract from the request
      4. \"error_handling\": How to handle failures

      Context: #{context}
      Request: #{user_request}

      Respond with only the JSON workflow.
      """

      case GroqClient.chat_completion(
             messages: [
               %{role: "system", content: system_prompt},
               %{role: "user", content: user_request}
             ]
           ) do
        {:ok, %{"choices" => [%{"message" => %{"content" => response}}]}} ->
          case Jason.decode(response) do
            {:ok, workflow} ->
              {:ok, workflow}

            {:error, _} ->
              # Fallback to template matching
              fallback_workflow(user_request)
          end

        {:error, reason} ->
          {:error, "Failed to generate workflow: #{reason}"}
      end
    end
  end

  defp fallback_workflow(user_request) do
    message_lower = String.downcase(user_request)

    cond do
      String.contains?(message_lower, "onboard") or String.contains?(message_lower, "new client") ->
        {:ok, Map.get(@workflow_templates, "client_onboarding")}

      String.contains?(message_lower, "follow") and String.contains?(message_lower, "meeting") ->
        {:ok, Map.get(@workflow_templates, "meeting_followup")}

      String.contains?(message_lower, "lead") or String.contains?(message_lower, "inquiry") ->
        {:ok, Map.get(@workflow_templates, "lead_qualification")}

      true ->
        # Generate simple single-step workflow
        {:ok,
         [
           %{
             "step" => 1,
             "action" => "search_emails",
             "api" => "gmail",
             "params" => %{"query" => user_request},
             "description" => "Search for relevant information",
             "fallback" => "general_assistance"
           }
         ]}
    end
  end

  defp enhance_appointment_workflow(workflow, user_request) do
    # Extract contact name/email from the request
    contact_info = extract_contact_from_request(user_request)

    # Enhance the workflow with extracted data and better error handling
    workflow
    |> Map.put("extracted_data", contact_info)
    |> Map.put("error_handling", %{
      "contact_not_found" => "Create contact in HubSpot and continue",
      "no_available_times" => "Get times for next week",
      "no_response" => "Send follow-up after 48 hours",
      "api_error" => "Retry with exponential backoff"
    })
    |> Map.put("llm_analysis", [
      "analyze_email_response",
      "extract_preferred_time",
      "determine_response_type"
    ])
  end

  defp extract_contact_from_request(request) do
    # Simple extraction - in practice, this would use LLM
    cond do
      String.contains?(request, "with") ->
        parts = String.split(request, "with")

        if length(parts) > 1 do
          contact_part = Enum.at(parts, 1) |> String.trim()
          %{"contact_name_or_email" => contact_part}
        else
          %{}
        end

      String.contains?(request, "@") ->
        # Extract email
        case Regex.run(~r/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/, request) do
          [email] -> %{"contact_email" => email}
          _ -> %{}
        end

      true ->
        %{}
    end
  end

  def execute_workflow(user, workflow, extracted_data \\ %{}) do
    # Sort steps by step number
    sorted_steps = Enum.sort_by(workflow["steps"], & &1["step"])

    # Execute steps in order, handling dependencies
    results =
      Enum.reduce(sorted_steps, %{}, fn step, acc ->
        case can_execute_step(step, acc) do
          true ->
            # Execute the step
            case execute_workflow_step(user, step, extracted_data, acc) do
              {:ok, result} ->
                Map.put(acc, "step_#{step["step"]}", result)

              {:error, reason} ->
                # Try fallback if available
                case step["fallback"] do
                  nil ->
                    Map.put(acc, "step_#{step["step"]}", %{error: reason})

                  fallback_action ->
                    case execute_fallback(user, fallback_action, step, extracted_data, acc) do
                      {:ok, fallback_result} ->
                        Map.put(acc, "step_#{step["step"]}", fallback_result)

                      {:error, fallback_reason} ->
                        Map.put(acc, "step_#{step["step"]}", %{
                          error: reason,
                          fallback_error: fallback_reason
                        })
                    end
                end
            end

          false ->
            # Step cannot be executed due to dependency
            Map.put(acc, "step_#{step["step"]}", %{error: "Dependency not met"})
        end
      end)

    {:ok, results}
  end

  defp can_execute_step(step, previous_results) do
    case step["depends_on"] do
      nil ->
        true

      depends_on ->
        # Check if the dependency step was successful
        case Map.get(previous_results, "step_#{depends_on}") do
          %{error: _} -> false
          nil -> false
          _ -> true
        end
    end
  end

  defp execute_workflow_step(user, step, extracted_data, previous_results) do
    # Extract data from previous steps if needed
    params = extract_step_params(step, extracted_data, previous_results)

    # Execute the action
    case step["api"] do
      "gmail" ->
        execute_gmail_action(user, step["action"], params)

      "calendar" ->
        execute_calendar_action(user, step["action"], params)

      "hubspot" ->
        execute_hubspot_action(user, step["action"], params)

      _ ->
        {:error, "Unknown API: #{step["api"]}"}
    end
  end

  defp execute_fallback(user, fallback_action, step, extracted_data, previous_results) do
    # Execute fallback action
    case fallback_action do
      "create_contact" ->
        execute_hubspot_action(user, "create_contact", %{
          "email" => "default@example.com",
          "name" => "Default Contact"
        })

      "general_assistance" ->
        {:ok, %{message: "I'll help you with this request manually"}}

      _ ->
        {:error, "Unknown fallback action: #{fallback_action}"}
    end
  end

  defp extract_step_params(step, extracted_data, previous_results) do
    # Extract parameters from previous steps or extracted data
    case step["extract_from"] do
      nil ->
        step["params"]

      extract_rules ->
        extract_params_from_previous(
          step["params"],
          extract_rules,
          previous_results,
          extracted_data
        )
    end
  end

  defp extract_params_from_previous(params, extract_rules, previous_results, extracted_data) do
    # Replace placeholders with actual data from previous steps
    Enum.reduce(params, %{}, fn {key, value}, acc ->
      case value do
        "extracted_email" ->
          Map.put(acc, key, Map.get(extracted_data, "email") || "default@example.com")

        "extracted_name" ->
          Map.put(acc, key, Map.get(extracted_data, "name") || "Default Name")

        "contact_email" ->
          Map.put(acc, key, Map.get(extracted_data, "email") || "default@example.com")

        "contact_id" ->
          Map.put(acc, key, Map.get(extracted_data, "contact_id") || "default_id")

        _ ->
          Map.put(acc, key, value)
      end
    end)
  end

  # API execution functions
  defp execute_gmail_action(user, action, params) do
    case action do
      "search_emails" ->
        query = Map.get(params, "query", "")
        AdvisorAi.Integrations.Gmail.search_emails(user, query)

      "send_email" ->
        to = Map.get(params, "to", "")
        subject = Map.get(params, "subject", "")
        body = Map.get(params, "body", "")
        AdvisorAi.Integrations.Gmail.send_email(user, to, subject, body)

      _ ->
        {:error, "Unknown Gmail action: #{action}"}
    end
  end

  defp execute_calendar_action(user, action, params) do
    case action do
      "get_availability" ->
        date = Map.get(params, "date", "today")
        duration = Map.get(params, "duration_minutes", 30)
        AdvisorAi.Integrations.Calendar.get_availability(user, date, duration)

      _ ->
        {:error, "Unknown Calendar action: #{action}"}
    end
  end

  defp execute_hubspot_action(user, action, params) do
    case action do
      "create_contact" ->
        AdvisorAi.Integrations.HubSpot.create_contact(user, params)

      "add_note" ->
        contact_email = Map.get(params, "contact_email", "")
        note_content = Map.get(params, "note_content", "")
        AdvisorAi.Integrations.HubSpot.add_note(user, contact_email, note_content)

      "search_contacts" ->
        query = Map.get(params, "query", "")
        AdvisorAi.Integrations.HubSpot.search_contacts(user, query)

      "list_contacts" ->
        limit = Map.get(params, "limit", 50)
        AdvisorAi.Integrations.HubSpot.list_contacts(user, limit)

      _ ->
        {:error, "Unknown HubSpot action: #{action}"}
    end
  end

  # Use LLM to decide next action: continue, ask user, edge case, or done
  def next_action_llm(workflow_state, recent_memories) do
    # Call LLM with workflow_state and recent_memories to decide next step
    # Placeholder: if last step result contains "need info", ask user
    last_result = List.last(workflow_state["results"] || [])

    if is_binary(last_result) and String.contains?(last_result, "need info") do
      {:ask_user, "Can you provide more details or clarification?"}
    else
      {:next_step, nil}
    end
  end

  # Use LLM/tool calling to resolve edge cases
  def resolve_edge_case(edge_case_info, workflow_state) do
    # Call LLM/tool with edge_case_info and workflow_state to resolve
    # This is a placeholder for LLM/tool integration
    # Example: {:ok, new_state} | {:done, result}
    {:ok, workflow_state}
  end
end
