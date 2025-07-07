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

  alias AdvisorAi.AI.OpenRouterClient

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
    ]
  }

  def generate_workflow(user_request, context \\ "") do
    # Use AI to analyze the request and generate a workflow
    system_prompt = """
    You are an expert workflow generator. Analyze the user's request and generate a detailed workflow.

    Available actions:
    - Gmail: search_emails, send_email, read_email, get_email_threads
    - Calendar: get_availability, schedule_meeting, get_events, update_event, delete_event
    - HubSpot: search_contacts, create_contact, update_contact, add_note, get_deals

    Generate a JSON workflow with:
    1. "workflow_name": Descriptive name
    2. "steps": Array of workflow steps, each with:
       - "step": Step number
       - "action": Action to perform
       - "api": Which API to use (gmail, calendar, hubspot)
       - "params": Parameters for the action
       - "description": What this step does
       - "depends_on": Step number this depends on (optional)
       - "fallback": Alternative action if this fails (optional)
       - "extract_from": What data to extract from previous steps (optional)

    3. "extractions": What data to extract from the request
    4. "error_handling": How to handle failures

    Context: #{context}
    Request: #{user_request}

    Respond with only the JSON workflow.
    """

    case OpenRouterClient.chat_completion(
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
end
