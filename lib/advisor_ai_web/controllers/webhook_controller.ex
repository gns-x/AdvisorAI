defmodule AdvisorAiWeb.WebhookController do
  use AdvisorAiWeb, :controller

  alias AdvisorAi.Accounts
  alias AdvisorAi.AI.Agent
  require Logger

  def gmail(conn, _params) do
    # Verify the webhook is from Gmail
    case verify_gmail_webhook(conn) do
      {:ok, _} ->
        # Process the webhook data
        case process_gmail_webhook(conn) do
          {:ok, message} ->
            # Trigger automation system for new emails
            trigger_email_automation(message)

            conn
            |> put_status(:ok)
            |> json(%{status: "success", message: "Gmail webhook processed"})

          {:error, reason} ->
            conn
            |> put_status(:bad_request)
            |> json(%{status: "error", message: reason})
        end

      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{status: "error", message: reason})
    end
  end

  def calendar(conn, params) do
    # Example: params = %{"user_id" => user_id, "event_data" => ...}
    user = Accounts.get_user(params["user_id"])

    if user do
      # Use universal agent to proactively handle calendar events
      case handle_proactive_calendar_event(user, params["event_data"] || %{}) do
        {:ok, result} ->
          require Logger
          Logger.info("✅ Proactive calendar handling completed: #{result}")

        {:error, reason} ->
          require Logger
          Logger.error("❌ Proactive calendar handling failed: #{reason}")
      end
    end

    conn |> put_status(:ok) |> json(%{status: "received"})
  end

  def hubspot(conn, params) do
    # Example: params = %{"user_id" => user_id, "hubspot_data" => ...}
    user = Accounts.get_user(params["user_id"])

    if user do
      # Use universal agent to proactively handle HubSpot events
      case handle_proactive_hubspot_event(user, params["hubspot_data"] || %{}) do
        {:ok, result} ->
          require Logger
          Logger.info("✅ Proactive HubSpot handling completed: #{result}")

        {:error, reason} ->
          require Logger
          Logger.error("❌ Proactive HubSpot handling failed: #{reason}")
      end
    end

    conn |> put_status(:ok) |> json(%{status: "received"})
  end

  # Manual email processing endpoint
  def process_manual_email(conn, params) do
    case params do
      %{
        "user_email" => user_email,
        "sender_email" => sender_email,
        "subject" => subject,
        "body" => body
      } ->
        case Accounts.get_user_by_email(user_email) do
          {:ok, user} ->
            # Create email data structure
            email_data = %{
              from: sender_email,
              subject: subject,
              body: body,
              received_at: DateTime.utc_now()
            }

            # Trigger automation system
            case Agent.handle_trigger(user, "email_received", email_data) do
              {:ok, result} ->
                conn
                |> put_status(:ok)
                |> json(%{
                  status: "success",
                  message: "Email automation triggered successfully",
                  result: result,
                  user: user_email,
                  sender: sender_email,
                  subject: subject
                })

              {:error, reason} ->
                conn
                |> put_status(:bad_request)
                |> json(%{
                  status: "error",
                  message: "Email automation failed",
                  error: reason,
                  user: user_email,
                  sender: sender_email
                })
            end

          {:error, :not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{status: "error", message: "User not found: #{user_email}"})

          {:error, reason} ->
            conn
            |> put_status(:bad_request)
            |> json(%{status: "error", message: "Error finding user: #{reason}"})
        end

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          status: "error",
          message: "Missing required parameters. Use: user_email, sender_email, subject, body"
        })
    end
  end

  # Test endpoint to manually trigger email automation
  def test_email_automation(conn, params) do
    # Get user by email from params
    case params do
      %{
        "user_email" => user_email,
        "sender_email" => sender_email,
        "subject" => subject,
        "body" => body
      } ->
        case Accounts.get_user_by_email(user_email) do
          {:ok, user} ->
            # Create a mock email message
            mock_message = %{
              "payload" => %{
                "headers" => [
                  %{"name" => "From", "value" => sender_email},
                  %{"name" => "To", "value" => user_email},
                  %{"name" => "Subject", "value" => subject}
                ],
                "body" => %{
                  "data" => Base.encode64(body)
                }
              }
            }

            # Trigger the automation
            trigger_email_automation(mock_message)

            conn
            |> put_status(:ok)
            |> json(%{
              status: "success",
              message: "Email automation triggered",
              user: user_email,
              sender: sender_email,
              subject: subject
            })

          {:error, :not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{status: "error", message: "User not found: #{user_email}"})

          {:error, reason} ->
            conn
            |> put_status(:bad_request)
            |> json(%{status: "error", message: "Error finding user: #{reason}"})
        end

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          status: "error",
          message: "Missing required parameters. Use: user_email, sender_email, subject, body"
        })
    end
  end

  # Trigger automation system for new emails
  defp trigger_email_automation(message) do
    # Extract user from the message
    case get_user_from_message(message) do
      {:ok, user} ->
        # Extract email data for automation
        email_data = extract_email_data_for_automation(message)

        # Use universal agent to proactively handle the email
        case handle_proactive_email_response(user, email_data) do
          {:ok, result} ->
            require Logger
            Logger.info("✅ Proactive email handling completed: #{result}")
            :ok

          {:error, reason} ->
            require Logger
            Logger.error("❌ Proactive email handling failed: #{reason}")
            :error
        end

      {:error, reason} ->
        require Logger
        Logger.error("Failed to get user from message: #{reason}")
        :error
    end
  end

  defp handle_proactive_email_response(user, email_data) do
    # Create a temporary conversation for the proactive response
    case AdvisorAi.Chat.create_conversation(%{
      user_id: user.id,
      title: "Proactive Response - #{email_data.subject}"
    }) do
      {:ok, conversation} ->
        # Build a proactive prompt for the AI to analyze and respond
        proactive_prompt = build_proactive_email_prompt(email_data)

        # Use enhanced universal agent to handle the email intelligently with memory and RAG
        case AdvisorAi.AI.UniversalAgent.process_proactive_request(user, conversation.id, proactive_prompt) do
          {:ok, _response} ->
            {:ok, "Proactive response generated"}

          {:error, reason} ->
            {:error, "Failed to generate proactive response: #{reason}"}
        end

      {:error, reason} ->
        {:error, "Failed to create conversation: #{reason}"}
    end
  end

  defp handle_proactive_calendar_event(user, event_data) do
    # Create a temporary conversation for the proactive response
    case AdvisorAi.Chat.create_conversation(%{
      user_id: user.id,
      title: "Calendar Event - #{event_data["summary"] || "New Event"}"
    }) do
      {:ok, conversation} ->
        # Build a proactive prompt for the AI to analyze and respond
        proactive_prompt = build_proactive_calendar_prompt(event_data)

        # Use enhanced universal agent to handle the calendar event intelligently with memory and RAG
        case AdvisorAi.AI.UniversalAgent.process_proactive_request(user, conversation.id, proactive_prompt) do
          {:ok, _response} ->
            {:ok, "Proactive calendar response generated"}

          {:error, reason} ->
            {:error, "Failed to generate proactive calendar response: #{reason}"}
        end

      {:error, reason} ->
        {:error, "Failed to create conversation: #{reason}"}
    end
  end

  defp handle_proactive_hubspot_event(user, hubspot_data) do
    # Create a temporary conversation for the proactive response
    case AdvisorAi.Chat.create_conversation(%{
      user_id: user.id,
      title: "HubSpot Event - #{hubspot_data["type"] || "Update"}"
    }) do
      {:ok, conversation} ->
        # Build a proactive prompt for the AI to analyze and respond
        proactive_prompt = build_proactive_hubspot_prompt(hubspot_data)

        # Use enhanced universal agent to handle the HubSpot event intelligently with memory and RAG
        case AdvisorAi.AI.UniversalAgent.process_proactive_request(user, conversation.id, proactive_prompt) do
          {:ok, _response} ->
            {:ok, "Proactive HubSpot response generated"}

          {:error, reason} ->
            {:error, "Failed to generate proactive HubSpot response: #{reason}"}
        end

      {:error, reason} ->
        {:error, "Failed to create conversation: #{reason}"}
    end
  end

  defp build_proactive_email_prompt(email_data) do
    """
    A new email was received that requires your attention:

    From: #{email_data.from}
    Subject: #{email_data.subject}
    Body: #{email_data.body}

    Please analyze this email and take appropriate action. Consider:

    1. **Meeting Lookup**: If this is from a client asking about an upcoming meeting, use the universal_action tool with action="find_meetings" and attendee_email="[sender_email]" to look up their meeting details in the calendar and respond with the information.

    2. **New Contact**: If this is from someone not in HubSpot, use universal_action with action="search_contacts" to check if they exist, then create them if needed and send a welcome email.

    3. **Meeting Request**: If this is a meeting request, use universal_action with action="get_availability" to check your calendar availability and respond with available times.

    4. **Follow-up**: Does this require any immediate action or follow-up?

    5. **HubSpot Notes**: Should I add any notes to HubSpot about this interaction?

    **SPECIFIC INSTRUCTIONS FOR MEETING LOOKUP:**
    - If the email mentions "meeting", "appointment", "call", "when", "schedule", "upcoming", "next", "our meeting", "the meeting", etc.
    - Extract the sender's email from the "From" field
    - Use universal_action with action="find_meetings" and attendee_email="[sender_email]"
    - If meetings are found, respond with the meeting details
    - If no meetings are found, let them know and offer to help schedule one

    **SPECIFIC INSTRUCTIONS FOR NEW CONTACTS:**
    - If the sender is not in HubSpot, add them using universal_action with action="create_contact"
    - Send them a welcome email using universal_action with action="send_email"
    - Add a note to HubSpot about this interaction

    Use the available tools to:
    - Search for the sender in HubSpot (universal_action with action="search_contacts")
    - Look up calendar events if they're asking about meetings (universal_action with action="find_meetings")
    - Send appropriate responses (universal_action with action="send_email")
    - Add notes to HubSpot (universal_action with action="add_note")
    - Create contacts if needed (universal_action with action="create_contact")

    Be proactive and helpful. If they're asking about a meeting, find it and tell them the details. If they're a new contact, add them to HubSpot and welcome them.

    **CRITICAL**: Always use the universal_action tool to perform real actions. Do not generate fake responses.
    """
  end

  defp build_proactive_calendar_prompt(event_data) do
    """
    A new calendar event was created that requires your attention:

    Event: #{event_data["summary"] || "Untitled Event"}
    Start: #{event_data["start"] || "Unknown"}
    End: #{event_data["end"] || "Unknown"}
    Attendees: #{inspect(event_data["attendees"] || [])}
    Description: #{event_data["description"] || "No description"}

    Please analyze this calendar event and take appropriate action. Consider:

    1. Are there attendees that need to be notified about this meeting? If so, send them an email with meeting details.

    2. Should I add a note to HubSpot about this meeting for any of the attendees?

    3. Is this a client meeting that requires preparation or follow-up?

    4. Should I send any reminders or confirmations?

    5. Does this meeting need any special handling based on the attendees or topic?

    Use the available tools to:
    - Send emails to attendees with meeting details
    - Add notes to HubSpot for attendees
    - Send meeting confirmations or reminders
    - Handle any special requirements

    Be proactive and helpful. If there are attendees, notify them about the meeting. If this is a client meeting, add appropriate notes to HubSpot.
    """
  end

  defp build_proactive_hubspot_prompt(hubspot_data) do
    """
    A HubSpot event occurred that requires your attention:

    Type: #{hubspot_data["type"] || "Unknown"}
    Action: #{hubspot_data["action"] || "Unknown"}
    Name: #{hubspot_data["name"] || "Unknown"}
    Email: #{hubspot_data["email"] || "Unknown"}
    Company: #{hubspot_data["company"] || "Unknown"}

    Please analyze this HubSpot event and take appropriate action. Consider:

    1. Is this a new contact that needs a welcome email? If so, send them a personalized welcome message.

    2. Is this a contact update that requires follow-up? If so, send them a relevant email.

    3. Should I add any notes to their HubSpot record about this interaction?

    4. Is this a client that needs special attention or onboarding?

    5. Should I schedule any follow-up meetings or calls?

    Use the available tools to:
    - Send welcome emails to new contacts
    - Send follow-up emails for updates
    - Add notes to HubSpot records
    - Schedule follow-up meetings
    - Handle any special requirements

    Be proactive and helpful. If this is a new contact, welcome them. If this is an update, follow up appropriately.
    """
  end

  # Extract user from Gmail message
  defp get_user_from_message(message) do
    # This would need to be implemented based on how you identify which user
    # the email belongs to. For now, we'll use a placeholder.
    # In a real implementation, you'd need to:
    # 1. Extract the email address from the message
    # 2. Find the user by their email
    # 3. Return the user record

    # Placeholder implementation
    case message do
      %{"payload" => %{"headers" => headers}} ->
        # Find the "To" header to get the recipient email
        to_header = Enum.find(headers, fn %{"name" => name} -> name == "To" end)

        case to_header do
          %{"value" => recipient_email} ->
            # Find user by email
            case Accounts.get_user_by_email(recipient_email) do
              {:ok, user} -> {:ok, user}
              {:error, :not_found} -> {:error, "User not found for email: #{recipient_email}"}
              {:error, reason} -> {:error, reason}
            end

          _ ->
            {:error, "No recipient email found in message"}
        end

      _ ->
        {:error, "Invalid message format"}
    end
  end

  # Extract email data for automation
  defp extract_email_data_for_automation(message) do
    case message do
      %{"payload" => %{"headers" => headers}} ->
        # Extract key email data
        from = extract_header_value(headers, "From")
        subject = extract_header_value(headers, "Subject")
        body = extract_email_body(message)

        %{
          from: from,
          subject: subject,
          body: body,
          received_at: DateTime.utc_now()
        }

      _ ->
        %{
          from: "unknown@example.com",
          subject: "Unknown Subject",
          body: "No body available",
          received_at: DateTime.utc_now()
        }
    end
  end

  # Extract header value from headers list
  defp extract_header_value(headers, header_name) do
    case Enum.find(headers, fn %{"name" => name} -> name == header_name end) do
      %{"value" => value} -> value
      _ -> "Unknown #{header_name}"
    end
  end

  # Extract email body from Gmail message
  defp extract_email_body(message) do
    # This is a simplified implementation
    # In a real implementation, you'd need to handle different MIME types
    # and extract the text content properly

    case message do
      %{"payload" => %{"body" => %{"data" => data}}} when is_binary(data) ->
        # Decode base64 data
        case Base.decode64(data, padding: false) do
          {:ok, decoded} -> decoded
          _ -> "Unable to decode email body"
        end

      %{"payload" => %{"parts" => parts}} when is_list(parts) ->
        # Handle multipart messages
        text_part =
          Enum.find(parts, fn part ->
            get_in(part, ["mimeType"]) == "text/plain"
          end)

        case text_part do
          %{"body" => %{"data" => data}} when is_binary(data) ->
            case Base.decode64(data, padding: false) do
              {:ok, decoded} -> decoded
              _ -> "Unable to decode email body"
            end

          _ ->
            "No text content found"
        end

      _ ->
        "No body content available"
    end
  end

  # Verify Gmail webhook authenticity
  defp verify_gmail_webhook(conn) do
    # In a real implementation, you would verify the webhook signature
    # For now, we'll just return success
    # TODO: Implement proper Gmail webhook verification
    {:ok, :verified}
  end

  # Process Gmail webhook data
  defp process_gmail_webhook(conn) do
    # Parse the webhook payload
    case conn.body_params do
      %{"message" => message} ->
        {:ok, message}

      %{"data" => data} when is_binary(data) ->
        # Handle base64 encoded data
        case Base.decode64(data, padding: false) do
          {:ok, decoded} ->
            case Jason.decode(decoded) do
              {:ok, %{"message" => message}} -> {:ok, message}
              {:ok, message} -> {:ok, message}
              {:error, _} -> {:error, "Invalid JSON in webhook data"}
            end

          {:error, _} ->
            {:error, "Invalid base64 data"}
        end

      _ ->
        {:error, "Invalid webhook payload"}
    end
  end
end
