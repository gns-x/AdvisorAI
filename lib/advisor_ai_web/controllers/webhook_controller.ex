defmodule AdvisorAiWeb.WebhookController do
  use AdvisorAiWeb, :controller

  alias AdvisorAi.Accounts
  alias AdvisorAi.AI.Agent
  alias AdvisorAi.Logger

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
      Agent.handle_trigger(user, "calendar_event", params["event_data"] || %{})
    end

    conn |> put_status(:ok) |> json(%{status: "received"})
  end

  def hubspot(conn, params) do
    # Example: params = %{"user_id" => user_id, "hubspot_data" => ...}
    user = Accounts.get_user(params["user_id"])

    if user do
      Agent.handle_trigger(user, "hubspot_update", params["hubspot_data"] || %{})
    end

    conn |> put_status(:ok) |> json(%{status: "received"})
  end

  # Manual email processing endpoint
  def process_manual_email(conn, params) do
    case params do
      %{"user_email" => user_email, "sender_email" => sender_email, "subject" => subject, "body" => body} ->
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
      %{"user_email" => user_email, "sender_email" => sender_email, "subject" => subject, "body" => body} ->
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
        # Get all active email instructions for this user
        case AdvisorAi.AI.AgentInstruction.get_active_instructions_by_trigger(user.id, "email_received") do
          {:ok, instructions} when is_list(instructions) and length(instructions) > 0 ->
            # Process each instruction
            Enum.each(instructions, fn instruction ->
              # Extract email data for automation
              email_data = extract_email_data_for_automation(message)

              # Execute the automation with the specific instruction
              AdvisorAi.AI.Agent.handle_trigger(user, "email_received", Map.put(email_data, :instruction, instruction.instruction))
            end)

          {:ok, _} ->
            # No active instructions
            :ok

          {:error, reason} ->
            Logger.error("Failed to get email instructions: #{reason}")
            :error
        end

      {:error, reason} ->
        Logger.error("Failed to get user from message: #{reason}")
        :error
    end
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
        text_part = Enum.find(parts, fn part ->
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
